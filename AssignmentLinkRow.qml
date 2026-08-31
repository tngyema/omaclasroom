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
  property color foreground
  property color muted
  property color accent
  property string fontFamily

  signal activated()

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
        anchors.right: parent.right
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
