import QtQuick
import qs.Commons

Item {
  id: row

  required property string title
  required property string subtitle
  required property bool submitted
  property bool showSubmissionStatus: true
  property bool locked: false
  property bool linkAvailable: false
  property string statusText: ""
  property color statusColor: row.muted
  property bool showSubmit: false
  property color foreground
  property color muted
  property color accent
  property string fontFamily

  signal activated()
  signal submitRequested()

  implicitHeight: summary.implicitHeight

  Column {
    id: summary
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Math.max(statusIcon.implicitHeight, titleText.implicitHeight)

      Text {
        id: statusIcon
        visible: row.locked || (row.showSubmissionStatus && row.submitted)
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: row.locked ? "\uf023" : "✓"
        textFormat: Text.PlainText
        color: linkArea.containsMouse ? row.accent : row.muted
        font.family: row.fontFamily
        font.pixelSize: Math.max(8, Style.font.body - 2)
      }

      Text {
        id: titleText
        anchors.left: statusIcon.visible ? statusIcon.right : parent.left
        anchors.leftMargin: statusIcon.visible ? Style.space(5) : 0
        anchors.right: statusBadge.visible ? statusBadge.left : (submitBtn.visible ? submitBtn.left : parent.right)
        anchors.rightMargin: statusBadge.visible ? Style.space(6) : (submitBtn.visible ? Style.space(6) : 0)
        text: row.title
        textFormat: Text.PlainText
        color: linkArea.containsMouse
          ? row.accent
          : ((row.showSubmissionStatus && row.submitted) || row.locked ? row.muted : row.foreground)
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        font.bold: !row.showSubmissionStatus || !row.submitted
        wrapMode: Text.WordWrap
      }

      Rectangle {
        id: statusBadge
        visible: row.statusText !== ""
        anchors.right: submitBtn.visible ? submitBtn.left : parent.right
        anchors.rightMargin: submitBtn.visible ? Style.space(6) : 0
        anchors.verticalCenter: parent.verticalCenter
        width: statusBadgeText.implicitWidth + Style.space(10)
        height: statusBadgeText.implicitHeight + Style.space(4)
        radius: Style.space(3)
        color: Qt.rgba(row.statusColor.r, row.statusColor.g, row.statusColor.b, 0.2)
        border.color: Qt.rgba(row.statusColor.r, row.statusColor.g, row.statusColor.b, 0.4)
        border.width: 1

        Text {
          id: statusBadgeText
          anchors.centerIn: parent
          text: row.statusText
          textFormat: Text.PlainText
          color: row.statusColor
          font.family: row.fontFamily
          font.pixelSize: Math.max(7, Style.font.caption - 1)
          font.bold: true
          font.letterSpacing: 0.8
        }
      }

      Rectangle {
        id: submitBtn
        visible: row.showSubmit && !row.submitted && !row.locked
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: submitBtnText.implicitWidth + Style.space(12)
        height: submitBtnText.implicitHeight + Style.space(6)
        radius: Style.space(4)
        color: submitBtnArea.containsMouse ? "#4caf50" : Qt.rgba(0.3, 0.7, 0.3, 0.3)
        border.color: submitBtnArea.containsMouse ? "#4caf50" : Qt.rgba(0.3, 0.7, 0.3, 0.5)
        border.width: 1

        Text {
          id: submitBtnText
          anchors.centerIn: parent
          text: "\uf00c Submit"
          textFormat: Text.PlainText
          color: submitBtnArea.containsMouse ? "#ffffff" : "#4caf50"
          font.family: row.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 1)
          font.bold: true
        }

        MouseArea {
          id: submitBtnArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: row.submitRequested()
        }
      }
    }

    Text {
      width: parent.width
      text: row.subtitle
      textFormat: Text.PlainText
      color: row.muted
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  MouseArea {
    id: linkArea
    anchors.fill: parent
    enabled: row.linkAvailable
    hoverEnabled: enabled
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: row.activated()
  }
}
