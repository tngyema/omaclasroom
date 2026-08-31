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
  property bool loading: false
  property bool refreshAfterStatus: false
  property var pendingVisibilityCourse: null
  property bool pendingHiddenState: false
  property bool hiddenCoursesExpanded: false
  property bool submittedAssignmentsExpanded: false

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
  readonly property var openAssignments: filterAssignments(assignments, false)
  readonly property var submittedAssignments: filterAssignments(assignments, true)
  readonly property var selectedCourse: findSelectedCourse()
  readonly property int selectedCourseIndex: findSelectedCourseIndex()
  readonly property var selectedCourseAssignments: selectedCourse
    ? (selectedCourse.assignments || []) : []
  readonly property var selectedCourseOpenAssignments:
    filterAssignments(selectedCourseAssignments, false)
  readonly property var selectedCourseSubmittedAssignments:
    filterAssignments(selectedCourseAssignments, true)
  readonly property var nextAssignment: teaching
    ? (assignments.length > 0 ? assignments[0] : null)
    : (openAssignments.length > 0 ? openAssignments[0] : null)
  readonly property int pendingCount: countAssignments(false)
  readonly property int submittedCount: assignments.length - pendingCount
  readonly property int draftCount: countDraftAssignments()
  readonly property int urgentCount: {
    var total = 0
    var cutoff = Date.now() + 2 * 24 * 60 * 60 * 1000
    for (var i = 0; i < assignments.length; i++) {
      var due = new Date(assignments[i].due_at).getTime()
      if (!assignments[i].submitted && isFinite(due) && due <= cutoff) total++
    }
    return total
  }

  onHiddenCoursesChanged: if (hiddenCourses.length === 0) hiddenCoursesExpanded = false
  onSubmittedCountChanged: if (submittedCount === 0) submittedAssignmentsExpanded = false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function alpha(color, amount) { return Qt.rgba(color.r, color.g, color.b, amount) }

  function boundedSetting(key, fallback, minimum, maximum) {
    var value = Number(setting(key, fallback))
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, Math.round(value)))
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

  function countAssignments(submitted) {
    var total = 0
    for (var i = 0; i < assignments.length; i++)
      if (!!assignments[i].submitted === submitted) total++
    return total
  }

  function filterAssignments(assignmentList, submitted) {
    var rows = []
    for (var i = 0; i < assignmentList.length; i++)
      if (!!assignmentList[i].submitted === submitted) rows.push(assignmentList[i])
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
    if (courses.length === 0) {
      selectedCourseId = ""
      return
    }
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

  function grade(course) {
    if (!course) return "No grade"
    if (course.current_grade !== null && course.current_grade !== undefined && course.current_grade !== "")
      return String(course.current_grade)
    if (course.current_score !== null && course.current_score !== undefined)
      return Number(course.current_score).toFixed(1) + "%"
    return "No grade"
  }

  function dueLabel(value) {
    var date = new Date(value)
    if (!isFinite(date.getTime())) return "No due date"
    return date.toLocaleString(Qt.locale(), "ddd MMM d, h:mm AP")
  }

  function assignmentSubtitle(assignment, includeCourse) {
    var parts = []
    if (includeCourse)
      parts.push(String(assignment.course_section || assignment.course_name || ""))
    parts.push("Due " + dueLabel(assignment.due_at))
    if (teaching && assignment.published !== null && assignment.published !== undefined)
      parts.push(assignment.published ? "Published" : "Draft")
    return parts.filter(function(part) { return part !== "" }).join(" · ")
  }

  function assignmentLocked(assignment) {
    if (!assignment) return false
    return !!assignment.locked
  }

  function courseStatus(course) {
    if (!course) return ""
    if (!teaching) return "Current grade  ·  " + grade(course)
    var state = course.courseState || ""
    var stateLabel = state === "ACTIVE" ? "Active"
      : (state === "ARCHIVED" ? "Archived" : "")
    return stateLabel !== "" ? stateLabel : "Unknown"
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
        + root.pendingCount + " assignment" + (root.pendingCount === 1 ? "" : "s")
        + " due · right-click to refresh")
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
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(680))

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
        ScrollBar.vertical: ScrollBar {
          id: panelScrollBar
          policy: ScrollBar.AsNeeded
        }

        Column {
          id: content
          width: panelFlick.width - panelScrollBar.implicitWidth - Style.space(4)
          spacing: Style.space(12)

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
                  + (root.loading ? " · REFRESHING" : (root.teaching
                    ? " · " + root.assignments.length + " DUE"
                    : " · " + root.pendingCount + " DUE"))
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }
          }

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

          Text {
            visible: root.visibilityError !== ""
            width: parent.width
            text: root.visibilityError
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Column {
            id: overviewPane
            visible: root.errorText === "" && root.roleError === "" && root.selectedPane === 0
            width: parent.width
            spacing: Style.space(12)

            Row {
              id: overviewSummary
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: root.teaching ? [
                  { value: root.assignments.length, label: "DUE", alarming: false },
                  { value: root.urgentCount, label: "48 HOURS", alarming: root.urgentCount > 0 },
                  { value: root.courses.length, label: "COURSES", alarming: false }
                ] : [
                  { value: root.pendingCount, label: "DUE", alarming: false },
                  { value: root.urgentCount, label: "48 HOURS", alarming: root.urgentCount > 0 },
                  { value: root.courses.length, label: "COURSES", alarming: false }
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
                    color: modelData.alarming ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }

            PanelSectionHeader {
              text: root.teaching ? "TEACHING COURSES" : "COURSE GRADES"
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
                    text: root.teaching
                      ? root.courseStatus(modelData)
                      : root.grade(modelData)
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
                ? "Next: " + root.dueLabel(root.nextAssignment.due_at) + " — " + root.nextAssignment.name
                : ""
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            id: assignmentsPane
            visible: root.errorText === "" && root.roleError === "" && root.selectedPane === 1
            width: parent.width
            spacing: Style.space(9)

            PanelSectionHeader {
              text: root.teaching
                ? "NEXT " + root.days + " DAYS · " + root.assignments.length
                  + " ASSIGNMENTS" + (root.draftCount > 0 ? " · " + root.draftCount + " DRAFT" + (root.draftCount === 1 ? "" : "S") : "")
                : "NEXT " + root.days + " DAYS · " + root.pendingCount + " OPEN"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.teaching
                ? root.assignments.length === 0
                : root.openAssignments.length === 0
              width: parent.width
              text: !root.teaching && root.submittedCount > 0
                ? "All upcoming assignments are submitted."
                : "No assignments are due in this window."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.teaching ? root.assignments : root.openAssignments
              Column {
                required property var modelData
                required property int index
                width: assignmentsPane.width
                spacing: Style.space(4)

                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: root.assignmentSubtitle(modelData, true)
                  submitted: !!modelData.submitted
                  showSubmissionStatus: !root.teaching
                  locked: root.assignmentLocked(modelData)
                  linkAvailable: (modelData.alternateLink || "") !== ""
                  foreground: root.foreground
                  muted: root.dim
                  accent: root.urgent
                  fontFamily: root.fontFamily
                  onActivated: root.openAssignment(modelData)
                }
                PanelSeparator {
                  visible: index < (root.teaching
                    ? root.assignments.length : root.openAssignments.length) - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }

            Button {
              visible: !root.teaching && root.submittedCount > 0
              width: parent.width
              text: root.submittedCount + " submitted assignment"
                + (root.submittedCount === 1 ? "" : "s")
              iconText: root.submittedAssignmentsExpanded ? "\uf078" : "\uf054"
              bordered: false
              leftAlign: true
              foreground: root.dim
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              iconSize: Style.font.caption
              horizontalPadding: 0
              onClicked: root.submittedAssignmentsExpanded = !root.submittedAssignmentsExpanded
            }

            Repeater {
              model: !root.teaching && root.submittedAssignmentsExpanded
                ? root.submittedAssignments : []
              Column {
                required property var modelData
                required property int index
                width: assignmentsPane.width
                spacing: Style.space(4)

                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: root.assignmentSubtitle(modelData, true)
                  submitted: true
                  showSubmissionStatus: true
                  locked: root.assignmentLocked(modelData)
                  linkAvailable: (modelData.alternateLink || "") !== ""
                  foreground: root.foreground
                  muted: root.dim
                  accent: root.urgent
                  fontFamily: root.fontFamily
                  onActivated: root.openAssignment(modelData)
                }
                PanelSeparator {
                  visible: index < root.submittedAssignments.length - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }
          }

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
                text: root.selectedCourse
                  ? root.courseLabel(root.selectedCourse, root.selectedCourseIndex) : ""
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

            PanelSectionHeader {
              visible: !!root.selectedCourse
              text: root.teaching
                ? "UPCOMING ASSIGNMENTS"
                : "UPCOMING ASSIGNMENTS · "
                  + root.selectedCourseOpenAssignments.length + " OPEN"
              foreground: root.foreground
              fontFamily: root.fontFamily
              topPadding: Math.ceil(fontSize * 0.15) + Style.space(4)
            }

            Text {
              visible: root.selectedCourse && (root.teaching
                ? root.selectedCourseAssignments.length === 0
                : root.selectedCourseOpenAssignments.length === 0)
              width: parent.width
              text: !root.teaching && root.selectedCourseSubmittedAssignments.length > 0
                ? "All upcoming assignments are submitted."
                : "No assignments due in the next " + root.days + " days."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.teaching
                ? root.selectedCourseAssignments : root.selectedCourseOpenAssignments
              Column {
                required property var modelData
                required property int index
                width: coursesPane.width
                spacing: Style.space(4)

                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: root.assignmentSubtitle(modelData, false)
                  submitted: !!modelData.submitted
                  showSubmissionStatus: !root.teaching
                  locked: root.assignmentLocked(modelData)
                  linkAvailable: (modelData.alternateLink || "") !== ""
                  foreground: root.foreground
                  muted: root.dim
                  accent: root.urgent
                  fontFamily: root.fontFamily
                  onActivated: root.openAssignment(modelData)
                }
                PanelSeparator {
                  visible: index < (root.teaching
                    ? root.selectedCourseAssignments.length
                    : root.selectedCourseOpenAssignments.length) - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }

            Button {
              visible: !root.teaching
                && root.selectedCourseSubmittedAssignments.length > 0
              width: parent.width
              text: root.selectedCourseSubmittedAssignments.length
                + " submitted assignment"
                + (root.selectedCourseSubmittedAssignments.length === 1 ? "" : "s")
              iconText: root.submittedAssignmentsExpanded ? "\uf078" : "\uf054"
              bordered: false
              leftAlign: true
              foreground: root.dim
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              iconSize: Style.font.caption
              horizontalPadding: 0
              onClicked: root.submittedAssignmentsExpanded = !root.submittedAssignmentsExpanded
            }

            Repeater {
              model: !root.teaching && root.submittedAssignmentsExpanded
                ? root.selectedCourseSubmittedAssignments : []
              Column {
                required property var modelData
                required property int index
                width: coursesPane.width
                spacing: Style.space(4)

                AssignmentLinkRow {
                  width: parent.width
                  title: String(modelData.name || "Untitled")
                  subtitle: root.assignmentSubtitle(modelData, false)
                  submitted: true
                  showSubmissionStatus: true
                  locked: root.assignmentLocked(modelData)
                  linkAvailable: (modelData.alternateLink || "") !== ""
                  foreground: root.foreground
                  muted: root.dim
                  accent: root.urgent
                  fontFamily: root.fontFamily
                  onActivated: root.openAssignment(modelData)
                }
                PanelSeparator {
                  visible: index < root.selectedCourseSubmittedAssignments.length - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.18
                }
              }
            }

            Button {
              visible: root.hiddenCourses.length > 0
              width: parent.width
              text: root.hiddenCourses.length + " hidden course"
                + (root.hiddenCourses.length === 1 ? "" : "s")
              iconText: root.hiddenCoursesExpanded ? "\uf078" : "\uf054"
              bordered: false
              leftAlign: true
              foreground: root.dim
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              iconSize: Style.font.caption
              horizontalPadding: 0
              onClicked: root.hiddenCoursesExpanded = !root.hiddenCoursesExpanded
            }

            Text {
              visible: root.hiddenCoursesExpanded && root.hiddenCourses.length > 0
              width: parent.width
              text: "Hidden courses are excluded from assignments, counts, and alerts."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.hiddenCoursesExpanded ? root.hiddenCourses : []
              Column {
                required property var modelData
                required property int index
                width: coursesPane.width
                spacing: Style.space(7)

                Item {
                  width: parent.width
                  implicitHeight: hiddenCourseText.implicitHeight

                  Column {
                    id: hiddenCourseText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(1)
                    Text {
                      width: parent.width
                      text: modelData.name
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                    Text {
                      visible: String(modelData.section || "") !== ""
                      width: parent.width
                      text: String(modelData.section || "")
                      textFormat: Text.PlainText
                      color: Qt.darker(root.dim, 1.25)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }

                PanelSeparator {
                  visible: index < root.hiddenCourses.length - 1
                  width: parent.width
                  foreground: root.foreground
                  opacity: 0.12
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
