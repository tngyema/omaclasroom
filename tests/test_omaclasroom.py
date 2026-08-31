import io
import json
import unittest
from datetime import datetime, timezone
import os
import stat
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch
from urllib.error import HTTPError
from urllib.request import Request

sys.path.insert(0, str(Path(__file__).parents[1]))
from importlib.machinery import SourceFileLoader

module = SourceFileLoader("omaclasroom", str(Path(__file__).parents[1] / "omaclasroom")).load_module()

MY_USER = "current_user"


class FakeClient:
    """Fake Google Classroom client for student-focused tests."""

    def list_courses(self):
        return [
            {"id": "1", "name": "Software Engineering", "section": "CSC3400",
             "alternateLink": "https://classroom.google.com/c/MDEwMTIz",
             "courseState": "ACTIVE"},
        ]

    def list_teachers(self, course_id):
        return []

    def list_course_work(self, course_id):
        return [
            {"id": "w1", "title": "In range", "dueDate": "2026-09-01T15:00:00Z",
             "alternateLink": "https://classroom.google.com/c/MDEwMTIz/a/Mjk4NzY",
             "published": True, "workType": "ASSIGNMENT"},
            {"id": "w2", "title": "Too late", "dueDate": "2026-09-20T15:00:00Z",
             "alternateLink": "https://classroom.google.com/c/MDEwMTIz/a/Mjk4Nzc",
             "published": True, "workType": "ASSIGNMENT"},
        ]


class MixedRoleClient:
    """Fake client with courses where the user is teacher of one and student of another."""

    def __init__(self):
        self.requested_course_ids = []
        self.work_requested_course_ids = []

    def list_courses(self):
        return [
            {"id": "10", "name": "Course I Teach", "section": "CS101",
             "alternateLink": "https://classroom.google.com/c/MDEw",
             "courseState": "ACTIVE"},
            {"id": "20", "name": "Course I Take", "section": "MATH200",
             "alternateLink": "https://classroom.google.com/c/MjAw",
             "courseState": "ACTIVE"},
        ]

    def list_teachers(self, course_id):
        self.requested_course_ids.append(course_id)
        if course_id == "10":
            return [{"userId": MY_USER, "emailAddress": "user@example.com"}]
        return []

    def list_course_work(self, course_id):
        self.work_requested_course_ids.append(course_id)
        return []


class TeacherClient:
    """Fake client returning teacher courses with published/draft status."""

    def __init__(self):
        self.requests = []

    def list_courses(self):
        return [{
            "id": "30", "name": "Human Computer Interaction", "section": "CSC4400",
            "alternateLink": "https://classroom.google.com/c/MzAw",
            "courseState": "ACTIVE",
        }]

    def list_teachers(self, course_id):
        return [{"userId": MY_USER, "emailAddress": "user@example.com"}]

    def list_course_work(self, course_id):
        self.requests.append(course_id)
        if course_id == "30":
            return [
                {"id": "w1", "title": "Prototype Review",
                 "dueDate": "2026-09-01T15:00:00Z",
                 "alternateLink": "https://classroom.google.com/c/MzAw/a/MzE",
                 "published": False, "workType": "ASSIGNMENT"},
                {"id": "w2", "title": "Too late",
                 "dueDate": "2026-09-20T15:00:00Z",
                 "alternateLink": "https://classroom.google.com/c/MzAw/a/MzI",
                 "published": True, "workType": "ASSIGNMENT"},
            ]
        return []


class PermissionLimitedClient:
    """Fake client that raises permission errors on list_courses."""

    def list_courses(self):
        raise module.ClassroomPermissionError("Google denied access to Classroom data")

    def list_teachers(self, course_id):
        return []

    def list_course_work(self, course_id):
        return []


class TeacherPermissionLimitedClient:
    """Fake client where list_teachers raises permission errors."""

    def list_courses(self):
        return [
            {"id": "10", "name": "Course I Teach", "section": "CS101",
             "alternateLink": "https://classroom.google.com/c/MDEw",
             "courseState": "ACTIVE"},
            {"id": "20", "name": "Course I Take", "section": "MATH200",
             "alternateLink": "https://classroom.google.com/c/MjAw",
             "courseState": "ACTIVE"},
        ]

    def list_teachers(self, course_id):
        raise module.ClassroomPermissionError("Cannot list teachers")

    def list_course_work(self, course_id):
        return []


class ClassroomTests(unittest.TestCase):
    def test_sanitizes_text_for_ui(self):
        self.assertEqual(
            module.sanitize_text("&lt;script&gt;alert(1)&lt;/script&gt;\x1b[31m"),
            "<script>alert(1)</script> [31m",
        )
        self.assertEqual(module.sanitize_text(None, "Untitled"), "Untitled")

    def test_validates_classroom_link(self):
        self.assertEqual(
            module.sanitize_classroom_link("https://classroom.google.com/c/MDE/a/Mjk"),
            "https://classroom.google.com/c/MDE/a/Mjk",
        )

    def test_rejects_non_classroom_link(self):
        for value in (
            "https://evil.example.com/collect",
            "http://classroom.google.com/c/MDE",
            "javascript:alert(1)",
            "https://classroom.google.com/c/MDE\nfile:///etc/passwd",
            None,
            "",
        ):
            with self.subTest(value=value):
                self.assertIsNone(module.sanitize_classroom_link(value))

    def test_collects_only_assignments_in_window(self):
        client = FakeClient()
        data = module.collect(
            client, 14, datetime(2026, 8, 27, tzinfo=timezone.utc),
            all_courses=client.list_courses(), my_user_id=MY_USER,
        )
        student = data["roles"]["student"]
        self.assertEqual(data["schema_version"], 1)
        self.assertEqual(len(student["courses"]), 1)
        self.assertEqual(
            [a["name"] for a in student["courses"][0]["assignments"]],
            ["In range"],
        )
        self.assertEqual(
            student["courses"][0]["assignments"][0]["alternateLink"],
            "https://classroom.google.com/c/MDEwMTIz/a/Mjk4NzY",
        )
        self.assertEqual(
            student["courses"][0]["alternateLink"],
            "https://classroom.google.com/c/MDEwMTIz",
        )
        self.assertFalse(data["roles"]["teacher"]["available"])

    def test_collects_teacher_courses_and_status(self):
        client = TeacherClient()
        data = module.collect(
            client, 14, datetime(2026, 8, 27, tzinfo=timezone.utc),
            all_courses=client.list_courses(), my_user_id=MY_USER,
        )
        teacher = data["roles"]["teacher"]
        course = teacher["courses"][0]
        assignment = course["assignments"][0]

        self.assertTrue(teacher["available"])
        self.assertEqual(course["courseState"], "ACTIVE")
        self.assertEqual(assignment["name"], "Prototype Review")
        self.assertFalse(assignment["published"])
        self.assertIn("30", client.requests)

    def test_permission_failure_does_not_discard_student_role(self):
        client = PermissionLimitedClient()
        data = module.collect(
            client, 14, datetime(2026, 8, 27, tzinfo=timezone.utc),
            all_courses=[], my_user_id=MY_USER,
        )

        self.assertEqual(data["roles"]["student"]["error"], "")
        self.assertEqual(data["roles"]["teacher"]["error"], "")

    def test_hidden_course_skips_assignment_request(self):
        client = MixedRoleClient()
        data = module.collect(
            client, 14, datetime(2026, 8, 27, tzinfo=timezone.utc),
            hidden_course_ids={"20"},
            all_courses=client.list_courses(), my_user_id=MY_USER,
        )

        student = data["roles"]["student"]
        self.assertEqual(student["courses"], [])
        self.assertEqual(
            [course["id"] for course in student["hidden_courses"]], ["20"],
        )
        self.assertNotIn("20", client.work_requested_course_ids)

    def test_hidden_teacher_course_skips_assignment_request(self):
        client = MixedRoleClient()
        data = module.collect(
            client, 14, datetime(2026, 8, 27, tzinfo=timezone.utc),
            hidden_course_ids={"10"},
            all_courses=client.list_courses(), my_user_id=MY_USER,
        )

        teacher = data["roles"]["teacher"]
        self.assertEqual(teacher["courses"], [])
        self.assertEqual(
            [course["id"] for course in teacher["hidden_courses"]], ["10"],
        )
        self.assertNotIn("10", client.work_requested_course_ids)

    def test_separates_student_and_teacher_courses(self):
        client = MixedRoleClient()
        data = module.collect(
            client, 14, datetime(2026, 8, 27, tzinfo=timezone.utc),
            all_courses=client.list_courses(), my_user_id=MY_USER,
        )

        self.assertEqual(
            [course["name"] for course in data["roles"]["student"]["courses"]],
            ["Course I Take"],
        )
        self.assertEqual(
            [course["name"] for course in data["roles"]["teacher"]["courses"]],
            ["Course I Teach"],
        )

    def test_hidden_course_preferences_are_written_privately_and_atomically(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "omaclasroom" / "hidden-courses.json"
            module.set_course_hidden(
                "20", True, "Orientation", "ORIENT", path,
            )

            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
            self.assertEqual(list(path.parent.glob(".hidden-courses.json.*.tmp")), [])

    def test_hidden_course_preferences_can_be_toggled(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "hidden-courses.json"
            module.set_course_hidden("20", True, "Orientation", "ORIENT", path)
            self.assertIn("20", module.hidden_courses_for(path))

            module.set_course_hidden("20", False, path=path)
            self.assertEqual(module.hidden_courses_for(path), {})

    def test_rejects_symlinked_hidden_course_preferences(self):
        with TemporaryDirectory() as directory:
            target = Path(directory) / "target.json"
            target.write_text(
                '{"version": 1, "instances": {"default": {}}}', encoding="utf-8",
            )
            path = Path(directory) / "hidden-courses.json"
            path.symlink_to(target)

            with self.assertRaisesRegex(RuntimeError, "symbolic link"):
                module.hidden_courses_for(path)

    def test_parse_time_handles_iso8601(self):
        result = module.parse_time("2026-09-01T15:00:00Z")
        self.assertIsNotNone(result)
        self.assertEqual(result.year, 2026)
        self.assertEqual(result.month, 9)

    def test_parse_time_returns_none_for_invalid(self):
        self.assertIsNone(module.parse_time(""))
        self.assertIsNone(module.parse_time(None))
        self.assertIsNone(module.parse_time("not-a-date"))

    def test_refresh_access_token_calls_google(self):
        response_body = json.dumps(
            {"access_token": "new-token", "token_type": "Bearer"}
        ).encode("utf-8")
        fake_response = Mock()
        fake_response.read.return_value = response_body
        fake_response.__enter__ = Mock(return_value=fake_response)
        fake_response.__exit__ = Mock(return_value=False)

        with patch.object(module, "build_opener") as mock_opener:
            mock_opener.return_value.open.return_value = fake_response
            token = module.refresh_access_token("id", "secret", "refresh-tok")
            self.assertEqual(token, "new-token")

    def test_refresh_access_token_raises_on_failure(self):
        error_body = json.dumps({"error": "invalid_grant"}).encode("utf-8")
        error = HTTPError(
            "https://oauth2.googleapis.com/token",
            400, "Bad Request", {},
            io.BytesIO(error_body),
        )
        with patch.object(module, "build_opener") as mock_opener:
            mock_opener.return_value.open.side_effect = error
            with self.assertRaisesRegex(
                module.ClassroomAuthenticationError, "Token refresh failed",
            ):
                module.refresh_access_token("id", "secret", "bad-refresh")

    def test_teacher_permission_failure_treated_as_no_teachers(self):
        client = TeacherPermissionLimitedClient()
        data = module.collect(
            client, 14, datetime(2026, 8, 27, tzinfo=timezone.utc),
            all_courses=client.list_courses(), my_user_id=MY_USER,
        )
        self.assertEqual(data["roles"]["student"]["error"], "")
        self.assertTrue(data["roles"]["student"]["available"])
        self.assertFalse(data["roles"]["teacher"]["available"])


if __name__ == "__main__":
    unittest.main()
