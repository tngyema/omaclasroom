import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.omaclasroom"
  ipcTarget: "io.github.omaclasroom"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color success: bar ? bar.success : "#4caf50"
  readonly property color warning: "#ff9800"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: decodeURIComponent(
    String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string helperPath: pluginDir + "/omaclasroom"
  readonly property int days: boundedSetting("days", 14, 1, 60)
  readonly property int refreshSec: boundedSetting("refreshIntervalSec", 21600, 300, 86400)

  readonly property var paneNames: ["Overview", "Assignments", "Courses"]
  property int selectedPane: 0
  property string selectedRole: "student"
  property bool cursorActive: false
  property string selectedCourseId: ""
  property var payload: ({
    schema_version: 1,
    fetched_at: "",
    days: 14,
    roles: {
      student: { available: false, error: "", courses: [], hidden_courses: [] },
      teacher: { available: false, error: "", courses: [], hidden_courses: [] }
    }
  })
  property string errorText: ""
  property string visibilityError: ""
  property string submitError: ""
  property bool loading: false
  property bool refreshAfterStatus: false
  property bool hiddenCoursesExpanded: false
  property bool submittedAssignmentsExpanded: false
  property bool missingExpanded: true
  property var pendingSubmitAssignment: null
  property string submitLinkId: ""

  readonly property var studentData: payload.roles && payload.roles.student
    ? payload.roles.student : ({ available: false, error: "", courses: [], hidden_courses: [] })
  readonly property var teacherData: payload.roles && payload.roles.teacher
    ? payload.roles.teacher : ({ available: false, error: "", courses: [], hidden_courses: [] })
  readonly property var activeRoleData: selectedRole === "teacher" ? teacherData : studentData
  readonly property bool teaching: selectedRole === "teacher"
  readonly property bool studentRolePresent: !!studentData.available || String(studentData.error || "") !== ""
  readonly property bool teacherRolePresent: !!teacherData.available || String(teacherData.error || "") !== ""
  readonly property bool showRoleSwitch: studentRolePresent && teacherRolePresent
  readonly property string roleError: String(activeRoleData.error || "")
  readonly property var courses: activeRoleData.courses || []
  readonly property var hiddenCourses: activeRoleData.hidden_courses || []
  readonly property var assignments: flattenAssignments(courses)
  readonly property var selectedCourse: findSelectedCourse()
  readonly property int selectedCourseIndex: findSelectedCourseIndex()
  readonly property var selectedCourseAssignments: selectedCourse
    ? (selectedCourse.assignments || []) : []

  readonly property var dueSoonAssignments: filterByStatus(assignments, "due_soon")
  readonly property var missingAssignments: filterByStatus(assignments, "missing")
  readonly property var submittedAssignments: filterByStatus(assignments, "submitted")
  readonly property var upcomingAssignments: filterByStatus(assignments, "upcoming")

  readonly property var nextAssignment: teaching
    ? (assignments.length > 0 ? assignments[0] : null)
    : (dueSoonAssignments.length > 0 ? dueSoonAssignments[0] : null)
  readonly property int dueSoonCount: dueSoonAssignments.length
  readonly property int missingCount: missingAssignments.length
  readonly property int submittedCount: submittedAssignments.length
  readonly property int upcomingCount: upcomingAssignments.length
  readonly property int draftCount: countDraftAssignments()
  readonly property int urgentCount: dueSoonCount

  property var now: new Date()
  Timer {
    interval: 60000
    running: root.opened
    repeat: true
    onTriggered: root.now = new Date()
  }

  onHiddenCoursesChanged: if (hiddenCourses.length === 0) hiddenCoursesExpanded = false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function alpha(color, amount) { return Qt.rgba(color.r, color.g, color.b, amount) }

  function boundedSetting(key, fallback, minimum, maximum) {
    var value = Number(setting(key, fallback))
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, Math.round(value)))
  }

  function getAssignmentStatus(assignment) {
    if (assignment.submitted) return "submitted"
    var due = new Date(assignment.due_at).getTime()
    if (!isFinite(due)) return "upcoming"
    var nowMs = now.getTime()
    var twoDaysMs = 2 * 24 * 60 * 60 * 1000
    if (due < nowMs) return "missing"
    if (due <= nowMs + twoDaysMs) return "due_soon"
    return "upcoming"
  }

  function filterByStatus(assignmentList, status) {
    var rows = []
    for (var i = 0; i < assignmentList.length; i++)
      if (getAssignmentStatus(assignmentList[i]) === status) rows.push(assignmentList[i])
    return rows
  }

  function flattenAssignments(courseList) {
    var rows = []
    for (var i = 0; i < courseList.length; i++) {
      var course = courseList[i]
      var courseAssignments = course.assignments || []
      for (var j = 0; j < courseAssignments.length; j++) {
        var source = courseAssignments[j]
        rows.push({
          id: source.id,
          name: source.name,
          due_at: source.due_at,
          due_dates: source.due_dates || [],
          submitted: source.submitted,
          published: source.published,
          locked: source.locked,
          missing: source.missing || false,
          alternateLink: source.alternateLink || "",
          course_id: course.id,
          course_name: course.name,
          course_section: course.section || ""
        })
      }
    }
    rows.sort(function(a, b) {
      return new Date(a.due_at).getTime() - new Date(b.due_at).getTime()
    })
    return rows
  }

  function countDraftAssignments() {
    var total = 0
    for (var i = 0; i < assignments.length; i++)
      if (assignments[i].published === false) total++
    return total
  }

  function ensureSelectedRole() {
    if (selectedRole === "teacher" && teacherRolePresent) return
    if (selectedRole === "student" && studentRolePresent) return
    if (studentRolePresent) selectedRole = "student"
    else if (teacherRolePresent) selectedRole = "teacher"
    else selectedRole = "student"
  }

  function selectRole(role) {
    if (role !== "student" && role !== "teacher") return
    if (role === "student" && !studentRolePresent) return
    if (role === "teacher" && !teacherRolePresent) return
    selectedRole = role
    selectedCourseId = ""
    hiddenCoursesExpanded = false
    submittedAssignmentsExpanded = false
    missingExpanded = true
    ensureSelectedCourse()
    if (panelFlick) panelFlick.contentY = 0
  }

  function findSelectedCourse() {
    for (var i = 0; i < courses.length; i++)
      if (String(courses[i].id) === selectedCourseId) return courses[i]
    return courses.length > 0 ? courses[0] : null
  }

  function findSelectedCourseIndex() {
    for (var i = 0; i < courses.length; i++)
      if (String(courses[i].id) === selectedCourseId) return i
    return courses.length > 0 ? 0 : -1
  }

  function ensureSelectedCourse() {
    if (courses.length === 0) { selectedCourseId = ""; return }
    for (var i = 0; i < courses.length; i++)
      if (String(courses[i].id) === selectedCourseId) return
    selectedCourseId = String(courses[0].id)
  }

  function selectPane(index) {
    selectedPane = ((index % paneNames.length) + paneNames.length) % paneNames.length
    cursorActive = true
    if (panelFlick) panelFlick.contentY = 0
  }

  function selectCourseOffset(offset) {
    if (courses.length === 0) return
    var index = ((selectedCourseIndex + offset) % courses.length + courses.length) % courses.length
    selectedCourseId = String(courses[index].id)
    if (panelFlick) panelFlick.contentY = 0
  }

  function refreshNow() {
    if (statusProc.running) return
    loading = true
    errorText = ""
    statusProc.running = true
  }

  function timeLeft(dueAt) {
    var due = new Date(dueAt).getTime()
    if (!isFinite(due)) return "No due date"
    var diff = due - now.getTime()
    if (diff < 0) {
      var past = -diff
      var days = Math.floor(past / 86400000)
      var hours = Math.floor((past % 86400000) / 3600000)
      if (days > 0) return days + "d " + hours + "h overdue"
      return hours + "h overdue"
    }
    var days = Math.floor(diff / 86400000)
    var hours = Math.floor((diff % 86400000) / 3600000)
    var mins = Math.floor((diff % 3600000) / 60000)
    if (days > 0) return days + "d " + hours + "h left"
    if (hours > 0) return hours + "h " + mins + "m left"
    return mins + "m left"
  }

  function dueDateTime(dueAt) {
    var date = new Date(dueAt)
    if (!isFinite(date.getTime())) return "No due date"
    return date.toLocaleString(Qt.locale(), "ddd MMM d, h:mm AP")
  }

  function statusLabel(assignment) {
    var status = getAssignmentStatus(assignment)
    if (status === "submitted") return "SUBMITTED"
    if (status === "missing") return "MISSING"
    if (status === "due_soon") return "DUE SOON"
    return "UPCOMING"
  }

  function statusColor(assignment) {
    var status = getAssignmentStatus(assignment)
    if (status === "submitted") return success
    if (status === "missing") return urgent
    if (status === "due_soon") return warning
    return dim
  }

  function grade(course) {
    if (!course) return "No grade"
    if (course.current_grade !== null && course.current_grade !== undefined && course.current_grade !== "")
      return String(course.current_grade)
    if (course.current_score !== null && course.current_score !== undefined)
      return Number(course.current_score).toFixed(1) + "%"
    return "No grade"
  }

  function courseStatus(course) {
    if (!course) return ""
    if (!teaching) return "Current grade  ·  " + grade(course)
    var state = course.courseState || ""
    return state === "ACTIVE" ? "Active" : state
  }

  function fetchedLabel() {
    var date = new Date(payload.fetched_at || "")
    if (!isFinite(date.getTime())) return loading ? "REFRESHING" : "NOT YET UPDATED"
    return "UPDATED " + date.toLocaleString(Qt.locale(), "h:mm AP")
  }

  function elidedLabel(value, maximumLength) {
    var label = String(value || "").trim()
    if (label.length <= maximumLength) return label
    return label.substring(0, maximumLength - 1) + "…"
  }

  function courseLabel(course, index) {
    var section = String(course.section || "").trim()
    if (section !== "") return elidedLabel(section, 20)
    return elidedLabel(course.name || ("Course " + (index + 1)), 20)
  }

  function openAssignment(assignment) {
    var url = assignment.alternateLink || ""
    if (url !== "") Qt.openUrlExternally(url)
  }

  function openCourse(course) {
    var url = course.alternateLink || ""
    if (url !== "") Qt.openUrlExternally(url)
  }

  function submitAssignment(assignment) {
    if (submitProc.running) return
    submitError = ""
    pendingSubmitAssignment = assignment
    submitProc.command = [
      helperPath, "submit",
      String(assignment.course_id),
      "--course-work-id", String(assignment.id),
    ]
    if (assignment.alternateLink)
      submitProc.command.push("--link-url", assignment.alternateLink)
    submitProc.running = true
  }

  Process {
    id: statusProc
    command: [root.helperPath, "fetch", "--json", "--days", String(root.days)]
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    stderr: StdioCollector { id: statusError; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0) {
        var message = String(statusError.text || "").trim()
        root.errorText = message !== "" ? message.replace(/^omaclasroom:\s*/, "")
                                            : "Google Classroom could not be refreshed."
        return
      }
      try {
        var nextPayload = JSON.parse(String(statusOutput.text || ""))
        if (Number(nextPayload.schema_version) !== 1 || !nextPayload.roles)
          throw new Error("Unsupported Omaclasroom data format")
        root.payload = nextPayload
        root.ensureSelectedRole()
        root.ensureSelectedCourse()
        root.errorText = ""
      } catch (error) {
        root.errorText = "Google Classroom returned data the bar could not read."
      }
      if (root.refreshAfterStatus) {
        root.refreshAfterStatus = false
        Qt.callLater(function() { root.refreshNow() })
      }
    }
  }

  Process {
    id: submitProc
    stdout: StdioCollector { id: submitOutput; waitForEnd: true }
    stderr: StdioCollector { id: submitErrorOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var message = String(submitErrorOutput.text || "").trim()
        root.submitError = message !== "" ? message.replace(/^omaclasroom:\s*/, "")
                                              : "Could not submit assignment."
      } else {
        root.submitError = ""
        root.pendingSubmitAssignment = null
        Qt.callLater(function() { root.refreshNow() })
      }
    }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNow()
  }

  Component.onCompleted: {}

  onOpenedChanged: if (opened) {
    cursorActive = false
    submittedAssignmentsExpanded = false
    missingExpanded = true
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: "io.github.omaclasroom"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function nextPane(): string { root.selectPane(root.selectedPane + 1); return root.paneNames[root.selectedPane] }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf19c"
    active: root.errorText !== "" || root.roleError !== "" || root.urgentCount > 0
    tooltipText: root.errorText !== ""
      ? "Omaclasroom — " + root.errorText
      : (root.roleError !== "" ? "Omaclasroom — " + root.roleError
      : "Omaclasroom — " + (root.teaching ? "Teaching · " : "Student · ")
        + root.dueSoonCount + " due soon · "
        + root.missingCount + " missing · right-click to refresh")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refreshNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.selectPane(root.selectedPane + dx)
        if (dy !== 0)
          panelFlick.contentY = Math.max(0, Math.min(
            panelFlick.contentY + dy * Style.space(56),
            Math.max(0, panelFlick.contentHeight - panelFlick.height)))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refreshNow()
        else if (text === "s" || text === "S") root.selectRole("student")
        else if (text === "t" || text === "T") root.selectRole("teacher")
        else if (text === "1") root.selectPane(0)
        else if (text === "2") root.selectPane(1)
        else if (text === "3") root.selectPane(2)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { id: panelScrollBar; policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width - panelScrollBar.implicitWidth - Style.space(4)
          spacing: Style.space(12)

          // ========== HEADER ==========
          Item {
            id: hero
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf19c"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Item {
                width: parent.width
                implicitHeight: Math.max(heroTitle.implicitHeight, roleChooser.implicitHeight)
                Text {
                  id: heroTitle
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Omaclasroom"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Item {
                  id: roleChooser
                  visible: root.showRoleSwitch
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: roleChooserText.implicitWidth
                  implicitHeight: roleChooserText.implicitHeight
                  Text {
                    id: roleChooserText
                    text: root.teaching ? "TEACHING" : "STUDENT"
                    color: roleChooserMouse.containsMouse ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.0
                  }
                  MouseArea {
                    id: roleChooserMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectRole(root.teaching ? "student" : "teacher")
                  }
                }
              }

              Text {
                width: parent.width
                text: root.fetchedLabel()
                  + (root.loading ? " · REFRESHING" : "")
                  + " · " + root.dueSoonCount + " DUE"
                  + (root.missingCount > 0 ? " · " + root.missingCount + " MISSING" : "")
                  + " · " + root.submittedCount + " DONE"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }
          }

          // ========== PANE SWITCHER ==========
          Row {
            id: paneSwitch
            width: parent.width
            spacing: Style.spacing.md
            readonly property real cellWidth: (width - spacing * (root.paneNames.length - 1)) / root.paneNames.length
            Repeater {
              model: root.paneNames
              Button {
                required property string modelData
                required property int index
                width: paneSwitch.cellWidth
                text: modelData
                selected: index === root.selectedPane
                hasCursor: root.cursorActive && index === root.selectedPane
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.selectPane(index)
                onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              }
            }
          }

          // ========== ERROR MESSAGES ==========
          Text {
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.submitError !== ""
            width: parent.width
            text: "Submit: " + root.submitError
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.errorText === "" && !root.loading
              && root.roleError === ""
              && root.courses.length === 0 && root.hiddenCourses.length === 0
            width: parent.width
            text: root.teaching
              ? "No active courses being taught were found."
              : "No active student courses were found."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.errorText === "" && root.roleError !== ""
            width: parent.width
            text: root.roleError
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          // ========== OVERVIEW PANE ==========
          Column {
            id: overviewPane
            visible: root.errorText === "" && root.roleError === "" && root.selectedPane === 0
            width: parent.width
            spacing: Style.space(12)

            Row {
              width: parent.width
              spacing: Style.space(8)
              Repeater {
                model: [
                  { value: root.dueSoonCount, label: "DUE SOON", alarming: root.dueSoonCount > 0, color: root.warning },
                  { value: root.missingCount, label: "MISSING", alarming: root.missingCount > 0, color: root.urgent },
                  { value: root.submittedCount, label: "DONE", alarming: false, color: root.success },
                  { value: root.courses.length, label: "COURSES", alarming: false, color: root.dim }
                ]
                Row {
                  required property var modelData
                  required property int index
                  spacing: Style.space(4)
                  Text {
                    visible: index > 0
                    text: "·"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: modelData.value + " " + modelData.label
                    color: modelData.alarming ? modelData.color : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "COURSES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.courses
              Column {
                required property var modelData
                required property int index
                width: overviewPane.width
                spacing: Style.space(7)
                Item {
                  width: parent.width
                  implicitHeight: Math.max(overviewName.implicitHeight, overviewGrade.implicitHeight)
                  Text {
                    id: overviewName
                    anchors.left: parent.left
                    anchors.right: overviewGrade.left
                    anchors.rightMargin: Style.space(12)
                    text: modelData.name
                    textFormat: Text.PlainText
                    color: overviewCourseLink.containsMouse ? root.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    MouseArea {
                      id: overviewCourseLink
                      anchors.fill: parent
                      enabled: (modelData.alternateLink || "") !== ""
                      hoverEnabled: enabled
                      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: root.openCourse(modelData)
                    }
                  }
                  Text {
                    id: overviewGrade
                    anchors.right: parent.right
                    text: root.grade(modelData)
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
                PanelSeparator {
                  visible: index < root.courses.length - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }

            Text {
              visible: !!root.nextAssignment
              width: parent.width
              text: root.nextAssignment
                ? "Next: " + dueDateTime(root.nextAssignment.due_at) + " — " + root.nextAssignment.name
                : ""
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ========== ASSIGNMENTS PANE ==========
          Column {
            id: assignmentsPane
            visible: root.errorText === "" && root.roleError === "" && root.selectedPane === 1
            width: parent.width
            spacing: Style.space(9)

            // --- DUE SOON SECTION ---
            PanelSectionHeader {
              text: "DUE SOON (" + root.dueSoonCount + ")"
              foreground: root.warning
              fontFamily: root.fontFamily
            }
            Text {
              visible: root.dueSoonCount === 0
              width: parent.width
              text: "No assignments due soon."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Repeater {
              model: root.dueSoonAssignments
              Column {
                required property var modelData
                required property int index
                width: assignmentsPane.width
                spacing: Style.space(4)
                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: dueDateTime(modelData.due_at) + " · " + timeLeft(modelData.due_at) + " · " + (modelData.course_section || modelData.course_name)
                  submitted: false
                  showSubmissionStatus: false
                  locked: false
                  linkAvailable: (modelData.alternateLink || "") !== ""
                  statusText: "DUE SOON"
                  statusColor: root.warning
                  showSubmit: !root.teaching
                  onActivated: root.openAssignment(modelData)
                  onSubmitRequested: root.submitAssignment(modelData)
                }
                PanelSeparator {
                  visible: index < root.dueSoonCount - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }

            // --- MISSING SECTION ---
            Item {
              width: parent.width
              implicitHeight: missingHeader.implicitHeight
              visible: root.missingCount > 0
              PanelSectionHeader {
                id: missingHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "MISSING (" + root.missingCount + ")"
                foreground: root.urgent
                fontFamily: root.fontFamily
              }
              Text {
                id: missingToggle
                visible: root.missingCount > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.missingExpanded ? "▼" : "▶"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.missingExpanded = !root.missingExpanded
                }
              }
            }
            Repeater {
              model: root.missingExpanded ? root.missingAssignments : []
              Column {
                required property var modelData
                required property int index
                width: assignmentsPane.width
                spacing: Style.space(4)
                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: dueDateTime(modelData.due_at) + " · " + timeLeft(modelData.due_at) + " · " + (modelData.course_section || modelData.course_name)
                  submitted: false
                  showSubmissionStatus: false
                  locked: false
                  linkAvailable: (modelData.alternateLink || "") !== ""
                  statusText: "MISSING"
                  statusColor: root.urgent
                  showSubmit: !root.teaching
                  onActivated: root.openAssignment(modelData)
                  onSubmitRequested: root.submitAssignment(modelData)
                }
                PanelSeparator {
                  visible: index < root.missingCount - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }

            // --- UPCOMING SECTION ---
            PanelSectionHeader {
              visible: root.upcomingCount > 0
              text: "UPCOMING (" + root.upcomingCount + ")"
              foreground: root.dim
              fontFamily: root.fontFamily
            }
            Repeater {
              model: root.upcomingAssignments
              Column {
                required property var modelData
                required property int index
                width: assignmentsPane.width
                spacing: Style.space(4)
                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: dueDateTime(modelData.due_at) + " · " + timeLeft(modelData.due_at) + " · " + (modelData.course_section || modelData.course_name)
                  submitted: false
                  showSubmissionStatus: false
                  locked: false
                  linkAvailable: (modelData.alternateLink || "") !== ""
                  statusText: "UPCOMING"
                  statusColor: root.dim
                  showSubmit: false
                  onActivated: root.openAssignment(modelData)
                }
                PanelSeparator {
                  visible: index < root.upcomingCount - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }

            // --- SUBMITTED SECTION ---
            Item {
              width: parent.width
              implicitHeight: submittedHeader.implicitHeight
              visible: root.submittedCount > 0
              PanelSectionHeader {
                id: submittedHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "SUBMITTED (" + root.submittedCount + ")"
                foreground: root.success
                fontFamily: root.fontFamily
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.submittedAssignmentsExpanded ? "▼" : "▶"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.submittedAssignmentsExpanded = !root.submittedAssignmentsExpanded
                }
              }
            }
            Repeater {
              model: root.submittedAssignmentsExpanded ? root.submittedAssignments : []
              Column {
                required property var modelData
                required property int index
                width: assignmentsPane.width
                spacing: Style.space(4)
                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: dueDateTime(modelData.due_at) + " · " + (modelData.course_section || modelData.course_name)
                  submitted: true
                  showSubmissionStatus: true
                  locked: false
                  linkAvailable: (modelData.alternateLink || "") !== ""
                  statusText: "SUBMITTED"
                  statusColor: root.success
                  showSubmit: false
                  onActivated: root.openAssignment(modelData)
                }
                PanelSeparator {
                  visible: index < root.submittedCount - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }
          }

          // ========== COURSES PANE ==========
          Column {
            id: coursesPane
            visible: root.errorText === "" && root.roleError === "" && root.selectedPane === 2
            width: parent.width
            spacing: Style.space(10)

            Item {
              visible: !!root.selectedCourse
              width: parent.width
              implicitHeight: coursePosition.implicitHeight
              PanelSectionHeader {
                id: coursePosition
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "COURSE " + (root.selectedCourseIndex + 1) + " OF " + root.courses.length
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
            }

            Item {
              visible: !!root.selectedCourse
              width: parent.width
              implicitHeight: Math.max(previousCourse.implicitHeight, courseName.implicitHeight, nextCourse.implicitHeight)
              PanelActionButton {
                id: previousCourse
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\uf053"
                tooltipText: "Previous course"
                enabled: root.courses.length > 1
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.selectCourseOffset(-1)
              }
              Text {
                id: courseName
                anchors.left: previousCourse.right
                anchors.right: nextCourse.left
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.selectedCourse ? root.courseLabel(root.selectedCourse, root.selectedCourseIndex) : ""
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }
              PanelActionButton {
                id: nextCourse
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\uf054"
                tooltipText: "Next course"
                enabled: root.courses.length > 1
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.selectCourseOffset(1)
              }
            }

            Text {
              id: selectedCourseTitle
              visible: !!root.selectedCourse
              width: parent.width
              text: root.selectedCourse ? root.selectedCourse.name : ""
              textFormat: Text.PlainText
              color: selectedCourseLink.containsMouse ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              MouseArea {
                id: selectedCourseLink
                anchors.fill: parent
                enabled: (root.selectedCourse && (root.selectedCourse.alternateLink || "") !== "")
                hoverEnabled: enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.openCourse(root.selectedCourse)
              }
            }

            Text {
              visible: !!root.selectedCourse
              width: parent.width
              text: root.courseStatus(root.selectedCourse)
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Repeater {
              model: root.selectedCourseAssignments
              Column {
                required property var modelData
                required property int index
                width: coursesPane.width
                spacing: Style.space(4)
                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: dueDateTime(modelData.due_at) + " · " + timeLeft(modelData.due_at)
                  submitted: root.getAssignmentStatus(modelData) === "submitted"
                  showSubmissionStatus: !root.teaching
                  locked: false
                  linkAvailable: (modelData.alternateLink || "") !== ""
                  statusText: root.statusLabel(modelData)
                  statusColor: root.statusColor(modelData)
                  showSubmit: !root.teaching && root.getAssignmentStatus(modelData) !== "submitted"
                  onActivated: root.openAssignment(modelData)
                  onSubmitRequested: root.submitAssignment(modelData)
                }
                PanelSeparator {
                  visible: index < root.selectedCourseAssignments.length - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground; opacity: 0.45 }

          Text {
            width: parent.width
            text: "Right-click or press R to refresh · ←/→ changes views"
              + (root.showRoleSwitch ? " · S/T changes role" : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
