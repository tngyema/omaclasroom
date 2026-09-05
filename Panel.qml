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

  readonly property var paneNames: ["Overview", "Assignments", "Missing", "Courses"]
  property int selectedPane: 0
  property string selectedRole: "student"
  property bool cursorActive: false
  property string selectedCourseId: ""
  property var payload: ({
    schema_version: 1, fetched_at: "", days: 14,
    roles: {
      student: { available: false, error: "", courses: [], hidden_courses: [] },
      teacher: { available: false, error: "", courses: [], hidden_courses: [] }
    }
  })
  property string errorText: ""
  property bool loading: false
  property bool refreshAfterStatus: false
  property bool submittedExpanded: false

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

  readonly property var allMissing: filterByStatus(assignments, "missing")
  readonly property var allDueSoon: filterByStatus(assignments, "due_soon")
  readonly property var allUpcoming: filterByStatus(assignments, "upcoming")
  readonly property var allSubmitted: filterByStatus(assignments, "submitted")

  readonly property var nextAssignment: teaching
    ? (assignments.length > 0 ? assignments[0] : null)
    : (allDueSoon.length > 0 ? allDueSoon[0] : null)
  readonly property int dueSoonCount: allDueSoon.length
  readonly property int missingCount: allMissing.length
  readonly property int submittedCount: allSubmitted.length
  readonly property int upcomingCount: allUpcoming.length
  readonly property int totalCount: assignments.length
  readonly property int urgentCount: {
    var count = 0
    var nowMs = now.getTime()
    for (var i = 0; i < assignments.length; i++) {
      if (assignments[i].submitted) continue
      var due = new Date(assignments[i].due_at).getTime()
      if (!isFinite(due)) continue
      var diff = due - nowMs
      if (diff > 0 && diff <= 86400000) count++
    }
    return count
  }

  function countByStatusForCourse(courseId, status) {
    var count = 0
    for (var i = 0; i < assignments.length; i++) {
      if (assignments[i].course_id === courseId && getAssignmentStatus(assignments[i]) === status) {
        count++
      }
    }
    return count
  }

  property var now: new Date()
  Timer { interval: 60000; running: root.opened; repeat: true; onTriggered: root.now = new Date() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function boundedSetting(key, fallback, minimum, maximum) {
    var value = Number(setting(key, fallback))
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, Math.round(value)))
  }

  function getAssignmentStatus(a) {
    if (a.submitted) return "submitted"
    var due = new Date(a.due_at).getTime()
    if (!isFinite(due)) return "upcoming"
    var nowMs = now.getTime()
    if (due < nowMs) return "missing"
    if (due <= nowMs + 2 * 86400000) return "due_soon"
    return "upcoming"
  }

  function filterByStatus(list, status) {
    var r = []
    for (var i = 0; i < list.length; i++) {
      if (getAssignmentStatus(list[i]) === status) r.push(list[i])
    }
    return r
  }

  function flattenAssignments(courseList) {
    var rows = []
    for (var i = 0; i < courseList.length; i++) {
      var course = courseList[i]
      for (var j = 0; j < (course.assignments || []).length; j++) {
        var s = course.assignments[j]
        rows.push({
          id: s.id, name: s.name, due_at: s.due_at,
          submitted: s.submitted, state: s.state || "UNKNOWN",
          published: s.published, missing: s.missing || false,
          alternateLink: s.alternateLink || "",
          course_id: course.id, course_name: course.name,
          course_section: course.section || ""
        })
      }
    }
    rows.sort(function(a, b) { return new Date(a.due_at).getTime() - new Date(b.due_at).getTime() })
    return rows
  }

  function ensureSelectedRole() {
    if (selectedRole === "teacher" && teacherRolePresent) return
    if (selectedRole === "student" && studentRolePresent) return
    selectedRole = studentRolePresent ? "student" : "teacher"
  }

  function selectRole(role) {
    if (role === "student" && !studentRolePresent) return
    if (role === "teacher" && !teacherRolePresent) return
    selectedRole = role
    selectedCourseId = ""
    submittedExpanded = false
    ensureSelectedCourse()
    if (panelFlick) panelFlick.contentY = 0
  }

  function findSelectedCourse() {
    for (var i = 0; i < courses.length; i++) {
      if (String(courses[i].id) === selectedCourseId) return courses[i]
    }
    return courses.length > 0 ? courses[0] : null
  }

  function findSelectedCourseIndex() {
    for (var i = 0; i < courses.length; i++) {
      if (String(courses[i].id) === selectedCourseId) return i
    }
    return courses.length > 0 ? 0 : -1
  }

  function ensureSelectedCourse() {
    if (courses.length === 0) { selectedCourseId = ""; return }
    for (var i = 0; i < courses.length; i++) {
      if (String(courses[i].id) === selectedCourseId) return
    }
    selectedCourseId = String(courses[0].id)
  }

  function selectPane(index) {
    selectedPane = ((index % paneNames.length) + paneNames.length) % paneNames.length
    cursorActive = true
    if (panelFlick) panelFlick.contentY = 0
  }

  function selectCourseOffset(offset) {
    if (courses.length === 0) return
    selectedCourseId = String(courses[((selectedCourseIndex + offset) % courses.length + courses.length) % courses.length].id)
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
    if (!isFinite(due)) return ""
    var diff = due - now.getTime()
    var suffix = diff < 0 ? " overdue" : " left"
    var past = Math.abs(diff)
    var days = Math.floor(past / 86400000)
    var hours = Math.floor((past % 86400000) / 3600000)
    var mins = Math.floor((past % 3600000) / 60000)
    var secs = Math.floor((past % 60000) / 1000)
    var parts = []
    if (days > 0) parts.push(days + "d")
    if (hours > 0) parts.push(hours + "h")
    if (mins > 0) parts.push(mins + "m")
    if (parts.length === 0) parts.push(secs + "s")
    return parts.join(" ") + suffix
  }

  function dueLabel(dueAt) {
    var d = new Date(dueAt)
    if (!isFinite(d.getTime())) return "No due date"
    var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var day = days[d.getDay()]
    var month = months[d.getMonth()]
    var date = d.getDate()
    var hours = d.getHours()
    var minutes = d.getMinutes()
    var ampm = hours >= 12 ? "PM" : "AM"
    var h12 = hours % 12 || 12
    var minStr = minutes < 10 ? "0" + minutes : String(minutes)
    return day + " " + month + " " + date + ", " + h12 + ":" + minStr + " " + ampm
  }

  function getTimezone() {
    var off = -new Date().getTimezoneOffset()
    var h = Math.floor(Math.abs(off) / 60)
    var m = Math.abs(off) % 60
    var sign = off >= 0 ? "+" : "-"
    return "UTC" + sign + h + (m > 0 ? ":" + (m < 10 ? "0" : "") + m : "")
  }

  function grade(course) {
    if (!course) return ""
    if (course.current_grade) return String(course.current_grade)
    if (course.current_score !== null && course.current_score !== undefined)
      return Number(course.current_score).toFixed(1) + "%"
    return ""
  }

  function fetchedLabel() {
    var d = new Date(payload.fetched_at || "")
    if (!isFinite(d.getTime())) return loading ? "Refreshing" : "Not yet updated"
    return "Updated " + d.toLocaleString(Qt.locale(), "h:mm AP")
  }

  function elided(v, max) {
    var s = String(v || "").trim()
    return s.length <= max ? s : s.substring(0, max - 1) + "..."
  }

  function courseLabel(c, i) {
    var s = String(c.section || "").trim()
    return s ? elided(s, 20) : elided(c.name || "Course " + (i + 1), 20)
  }

  function openLink(url) { if (url) Qt.openUrlExternally(url) }

  function submitAssignment(assignment) {
    var url = assignment.alternateLink || ""
    if (!url) url = "https://classroom.google.com"
    Qt.openUrlExternally(url)
  }

  Process {
    id: statusProc
    command: [root.helperPath, "fetch", "--json", "--days", String(root.days)]
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    stderr: StdioCollector { id: statusError; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0) {
        root.errorText = String(statusError.text || "").trim().replace(/^omaclasroom:\s*/, "") || "Could not refresh."
        return
      }
      try {
        var p = JSON.parse(String(statusOutput.text || ""))
        if (Number(p.schema_version) !== 1 || !p.roles) throw new Error("bad format")
        root.payload = p
        root.ensureSelectedRole()
        root.ensureSelectedCourse()
        root.errorText = ""
      } catch (e) {
        root.errorText = "Could not parse Classroom data."
      }
      if (root.refreshAfterStatus) {
        root.refreshAfterStatus = false
        Qt.callLater(root.refreshNow)
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

  onOpenedChanged: if (opened) {
    cursorActive = false
    submittedExpanded = false
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: "io.github.omaclasroom"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰋀"
    active: root.errorText !== "" || root.missingCount > 0 || root.urgentCount > 0
    tooltipText: root.errorText !== "" ? "Omaclasroom -- " + root.errorText
      : root.urgentCount > 0 ? "REMINDER: " + root.urgentCount + " assignment(s) due within 1 day!"
      : "Omaclasroom -- " + root.dueSoonCount + " due, " + root.missingCount + " missing, " + root.upcomingCount + " upcoming, " + root.submittedCount + " done"
    onPressed: function(btn) {
      if (btn === Qt.RightButton) root.refreshNow()
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
        if (dy !== 0) panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentY + dy * Style.space(40), Math.max(0, panelFlick.contentHeight - panelFlick.height)))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "s" || t === "S") root.selectRole("student")
        else if (t === "t" || t === "T") root.selectRole("teacher")
        else if (t === "1") root.selectPane(0)
        else if (t === "2") root.selectPane(1)
        else if (t === "3") root.selectPane(2)
        else if (t === "4") root.selectPane(3)
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

        Column {
          id: content
          width: panelFlick.width - Style.space(8)
          spacing: Style.space(10)
          anchors.horizontalCenter: parent.horizontalCenter

          // HEADER
          Item {
            width: parent.width
            implicitHeight: Math.max(hIcon.implicitHeight, hCol.implicitHeight)
            Text {
              id: hIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
    text: "󰋀"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
            Column {
              id: hCol
              anchors.left: hIcon.right
              anchors.leftMargin: Style.space(12)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2
              Item {
                width: parent.width
                implicitHeight: Math.max(hTitle.implicitHeight, roleCh.implicitHeight)
                Text {
                  id: hTitle
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Omaclasroom"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Item {
                  id: roleCh
                  visible: root.showRoleSwitch
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    text: root.teaching ? "TEACHING" : "STUDENT"
                    color: rArea.containsMouse ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.0
                  }
                  MouseArea {
                    id: rArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectRole(root.teaching ? "student" : "teacher")
                  }
                }
              }
              Text {
                width: parent.width
                text: root.fetchedLabel() + (root.loading ? " | refreshing" : "") + " | " + root.dueSoonCount + " due | " + root.missingCount + " missing | " + root.upcomingCount + " upcoming | " + root.submittedCount + " done | " + root.getTimezone()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
                elide: Text.ElideRight
              }
            }
          }

          // PANE SWITCHER
          Row {
            width: parent.width
            spacing: Style.spacing.md
            readonly property real cw: (width - spacing * 3) / 4
            Repeater {
              model: root.paneNames
              Button {
                required property string modelData
                required property int index
                width: parent.parent.cw
                text: modelData
                selected: index === root.selectedPane
                hasCursor: root.cursorActive && index === root.selectedPane
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.selectPane(index)
                onHovered: function(h) { if (h) root.cursorActive = true }
              }
            }
          }

          // ERRORS
          Text {
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
          Text {
            visible: root.errorText === "" && !root.loading && root.courses.length === 0
            width: parent.width
            text: "No courses found."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // REMINDER BANNER
          Column {
            visible: root.urgentCount > 0 && root.selectedPane === 0 && root.errorText === ""
            width: parent.width
            spacing: 4
            Rectangle {
              width: parent.width
              height: urgentCol.implicitHeight + 12
              radius: 4
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
              border.width: 1
              Column {
                id: urgentCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                  text: "REMINDER"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }
                Repeater {
                  model: {
                    var items = []
                    var nowMs = root.now.getTime()
                    for (var i = 0; i < root.assignments.length; i++) {
                      var a = root.assignments[i]
                      if (a.submitted) continue
                      var due = new Date(a.due_at).getTime()
                      if (!isFinite(due)) continue
                      var diff = due - nowMs
                      if (diff > 0 && diff <= 86400000) items.push(a)
                    }
                    return items
                  }
                  Text {
                    text: modelData.name + " — " + root.timeLeft(modelData.due_at) + " left"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                    width: parent.width
                  }
                }
              }
            }
          }

          // ==================== OVERVIEW ====================
          Column {
            visible: root.selectedPane === 0 && root.errorText === ""
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "SUMMARY"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
            Row {
              width: parent.width
              spacing: Style.space(16)
              Column {
                spacing: 2
                Text { text: String(root.totalCount); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
                Text { text: "Total"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }
              Column {
                spacing: 2
                Text { text: String(root.dueSoonCount); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
                Text { text: "Due soon"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }
              Column {
                spacing: 2
                Text { text: String(root.upcomingCount); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
                Text { text: "Upcoming"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }
              Column {
                spacing: 2
                Text { text: String(root.missingCount); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
                Text { text: "Missing"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }
              Column {
                spacing: 2
                Text { text: String(root.submittedCount); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
                Text { text: "Done"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) }

            Text {
              text: "COURSES"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
            Repeater {
              model: root.courses
              Column {
                required property var modelData
                required property int index
                width: parent.width
                spacing: 4
                Item {
                  width: parent.width
                  implicitHeight: Math.max(cName.implicitHeight, cGrade.implicitHeight)
                  Text {
                    id: cName
                    anchors.left: parent.left
                    anchors.right: cGrade.left
                    anchors.rightMargin: 8
                    text: modelData.name
                    color: cLink.containsMouse ? root.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    MouseArea {
                      id: cLink
                      anchors.fill: parent
                      enabled: (modelData.alternateLink || "") !== ""
                      hoverEnabled: enabled
                      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: root.openLink(modelData.alternateLink)
                    }
                  }
                  Text {
                    id: cGrade
                    anchors.right: parent.right
                    text: root.grade(modelData)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) }
              }
            }

            Text {
              visible: !!root.nextAssignment
              width: parent.width
              text: root.nextAssignment ? "Next: " + dueLabel(root.nextAssignment.due_at) + " — " + root.nextAssignment.name : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ==================== ASSIGNMENTS ====================
          Column {
            visible: root.selectedPane === 1 && root.errorText === ""
            width: parent.width
            spacing: Style.space(8)

            // DUE SOON
            Text {
              text: "DUE SOON (" + root.dueSoonCount + ")"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
            Text {
              visible: root.dueSoonCount === 0
              width: parent.width
              text: "Nothing due soon."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Repeater {
              model: root.allDueSoon
              delegate: Column {
                width: parent.width
                spacing: 4
                Item {
                  width: parent.width
                  implicitHeight: Math.max(dsName.implicitHeight, dsOpen.implicitHeight) + dsDue.implicitHeight + 4
                  Column {
                    anchors.left: parent.left
                    anchors.right: dsOpen.visible ? dsOpen.left : parent.right
                    anchors.rightMargin: dsOpen.visible ? 8 : 0
                    spacing: 2
                    Text { id: dsName; width: parent.width; text: modelData.name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight; maximumLineCount: 1 }
                    Text { id: dsDue; width: parent.width; text: dueLabel(modelData.due_at) + " | " + timeLeft(modelData.due_at) + " | " + (modelData.course_section || modelData.course_name); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                  }
                  Rectangle {
                    id: dsOpen
                    visible: (modelData.alternateLink || "") !== ""
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: dsOpenTxt.implicitWidth + 14
                    height: dsOpenTxt.implicitHeight + 8
                    radius: 4
                    color: dsOpenArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) : "transparent"
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                    border.width: 1
                    Text { id: dsOpenTxt; anchors.centerIn: parent; text: "Open"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                    MouseArea { id: dsOpenArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openLink(modelData.alternateLink) }
                  }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) }
              }
            }

            // UPCOMING
            Text {
              text: "UPCOMING (" + root.upcomingCount + ")"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              topPadding: 8
            }
            Repeater {
              model: root.allUpcoming
              delegate: Column {
                width: parent.width
                spacing: 4
                Item {
                  width: parent.width
                  implicitHeight: Math.max(upName.implicitHeight, upOpen.implicitHeight) + upDue.implicitHeight + 4
                  Column {
                    anchors.left: parent.left
                    anchors.right: upOpen.visible ? upOpen.left : parent.right
                    anchors.rightMargin: upOpen.visible ? 8 : 0
                    spacing: 2
                    Text { id: upName; width: parent.width; text: modelData.name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight; maximumLineCount: 1 }
                    Text { id: upDue; width: parent.width; text: dueLabel(modelData.due_at) + " | " + timeLeft(modelData.due_at) + " | " + (modelData.course_section || modelData.course_name); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                  }
                  Rectangle {
                    id: upOpen
                    visible: (modelData.alternateLink || "") !== ""
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: upOpenTxt.implicitWidth + 14
                    height: upOpenTxt.implicitHeight + 8
                    radius: 4
                    color: upOpenArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) : "transparent"
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                    border.width: 1
                    Text { id: upOpenTxt; anchors.centerIn: parent; text: "Open"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                    MouseArea { id: upOpenArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openLink(modelData.alternateLink) }
                  }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) }
              }
            }

            // TURNED IN
            Text {
              visible: root.submittedCount > 0
              text: "TURNED IN (" + root.submittedCount + ")"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              topPadding: 8
            }
            Repeater {
              model: root.allSubmitted
              delegate: Column {
                width: parent.width
                spacing: 4
                Item {
                  width: parent.width
                  implicitHeight: Math.max(cmName.implicitHeight, cmOpen.implicitHeight) + cmDue.implicitHeight + 4
                  Column {
                    anchors.left: parent.left
                    anchors.right: cmOpen.visible ? cmOpen.left : parent.right
                    anchors.rightMargin: cmOpen.visible ? 8 : 0
                    spacing: 2
                    Text { id: cmName; width: parent.width; text: modelData.name; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight; maximumLineCount: 1 }
                    Text { id: cmDue; width: parent.width; text: dueLabel(modelData.due_at) + " | " + (modelData.course_section || modelData.course_name); color: Qt.darker(root.dim, 1.3); font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                  }
                  Rectangle {
                    id: cmOpen
                    visible: (modelData.alternateLink || "") !== ""
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: cmOpenTxt.implicitWidth + 14
                    height: cmOpenTxt.implicitHeight + 8
                    radius: 4
                    color: cmOpenArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) : "transparent"
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                    border.width: 1
                    Text { id: cmOpenTxt; anchors.centerIn: parent; text: "Open"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                    MouseArea { id: cmOpenArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openLink(modelData.alternateLink) }
                  }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) }
              }
            }
          }

          // ==================== MISSING ====================
          Column {
            visible: root.selectedPane === 2 && root.errorText === ""
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "MISSING (" + root.missingCount + ")"
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
            Text {
              visible: root.missingCount === 0
              width: parent.width
              text: "Nothing missing. Good job!"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Repeater {
              model: root.allMissing
              Column {
                required property var modelData
                required property int index
                width: parent.width
                spacing: 4
                Item {
                  width: parent.width
                  implicitHeight: mTitle.implicitHeight + mSub.implicitHeight + 4
                  Column {
                    anchors.left: parent.left
                    anchors.right: submitBtn2.left
                    anchors.rightMargin: 8
                    spacing: 2
                    Text { id: mTitle; width: parent.width; text: modelData.name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight; maximumLineCount: 1 }
                    Text { id: mSub; width: parent.width; text: dueLabel(modelData.due_at) + " | " + timeLeft(modelData.due_at) + " | " + (modelData.course_section || modelData.course_name); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                  }
                  Rectangle {
                    id: submitBtn2
                    visible: !root.teaching
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: sText2.implicitWidth + 14
                    height: sText2.implicitHeight + 8
                    radius: 4
                    color: sArea2.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) : "transparent"
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                    border.width: 1
                    Text { id: sText2; anchors.centerIn: parent; text: "Open"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                    MouseArea { id: sArea2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.submitAssignment(modelData) }
                  }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) }
              }
            }
          }

          // ==================== COURSES ====================
          Column {
            visible: root.selectedPane === 3 && root.errorText === ""
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: cPos.implicitHeight
              Text {
                id: cPos
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "COURSE " + (root.selectedCourseIndex + 1) + " OF " + root.courses.length
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(pCourse.implicitHeight, cLabel.implicitHeight, nCourse.implicitHeight)
              PanelActionButton { id: pCourse; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; iconText: "\uf053"; enabled: root.courses.length > 1; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.selectCourseOffset(-1) }
              Text { id: cLabel; anchors.left: pCourse.right; anchors.right: nCourse.left; anchors.leftMargin: 8; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: root.selectedCourse ? root.courseLabel(root.selectedCourse, root.selectedCourseIndex) : ""; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
              PanelActionButton { id: nCourse; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; iconText: "\uf054"; enabled: root.courses.length > 1; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.selectCourseOffset(1) }
            }

            Text {
              visible: !!root.selectedCourse
              width: parent.width
              text: root.selectedCourse ? root.selectedCourse.name : ""
              color: cTitleLink.containsMouse ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              MouseArea {
                id: cTitleLink
                anchors.fill: parent
                enabled: (root.selectedCourse && (root.selectedCourse.alternateLink || "") !== "")
                hoverEnabled: enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.openLink(root.selectedCourse.alternateLink)
              }
            }

            // Per-course summary
            Item {
              visible: !!root.selectedCourse && root.selectedCourseAssignments.length > 0
              width: parent.width
              implicitHeight: summaryRow.implicitHeight
              Row {
                id: summaryRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(16)
                Column { spacing: 2
                  Text { text: root.selectedCourse ? String(root.countByStatusForCourse(root.selectedCourse.id, "due_soon")) : "0"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                  Text { text: "Due soon"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                }
                Column { spacing: 2
                  Text { text: root.selectedCourse ? String(root.countByStatusForCourse(root.selectedCourse.id, "missing")) : "0"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                  Text { text: "Missing"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                }
                Column { spacing: 2
                  Text { text: root.selectedCourse ? String(root.countByStatusForCourse(root.selectedCourse.id, "submitted")) : "0"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                  Text { text: "Done"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                }
              }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) }

            Repeater {
              model: root.selectedCourseAssignments
              Column {
                required property var modelData
                required property int index
                width: parent.width
                spacing: 4
                Item {
                  width: parent.width
                  implicitHeight: coTitle.implicitHeight + coSub.implicitHeight + 4
                  Column {
                    anchors.left: parent.left
                    anchors.right: coSubmit.left
                    anchors.rightMargin: 8
                    spacing: 2
                    Text { id: coTitle; width: parent.width; text: modelData.name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight; maximumLineCount: 1 }
                    Text { id: coSub; width: parent.width; text: dueLabel(modelData.due_at) + " | " + timeLeft(modelData.due_at); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                  }
                  Rectangle {
                    id: coSubmit
                    visible: !root.teaching && root.getAssignmentStatus(modelData) !== "submitted"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: coSText.implicitWidth + 14
                    height: coSText.implicitHeight + 8
                    radius: 4
                    color: coSArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) : "transparent"
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                    border.width: 1
                    Text { id: coSText; anchors.centerIn: parent; text: "Open"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                    MouseArea { id: coSArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.submitAssignment(modelData) }
                  }
                  Text {
                    visible: root.getAssignmentStatus(modelData) === "submitted"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Done"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) }
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3) }
          Text {
            width: parent.width
            text: "R refresh | 1-4 switch views | S/T switch role"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
