import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PanelWindow {
  id: root

  property bool active: false
  property bool micLive: false
  property bool inVoice: false
  property bool sharingScreen: false
  property string channel: ""
  property real audioPeak: 0

  signal toggleMicRequested()
  signal stopShareRequested()

  property real presence: active ? 1.0 : 0.0
  Behavior on presence {
    NumberAnimation {
      duration: root.active ? 220 : 300
      easing.type: root.active ? Easing.OutBack : Easing.InCubic
    }
  }

  visible: presence > 0.005
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "discord-mic-hud"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region { item: pill }

  Item {
    id: pill
    readonly property bool hovered: dragArea.containsMouse || micMouse.containsMouse || shareMouse.containsMouse
    opacity: root.presence * (hovered ? 0.97 : 0.87)
    Behavior on opacity {
      NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
    width: contentRow.implicitWidth + Style.space(26)
    height: Style.space(48)
    scale: 0.90 + 0.10 * root.presence
    // Default centered at bottom, custom x/y once dragged
    property bool moved: false
    property real customX: 0
    property real customY: 0

    x: moved ? customX : Math.round((root.width - width) / 2)
    y: moved ? customY : Math.round(root.height - height - Style.space(36) + (1.0 - root.presence) * Style.space(20))

    // Outer breathing aura ring
    Rectangle {
      anchors.centerIn: parent
      width: parent.width + Style.space(10) + root.audioPeak * Style.space(8)
      height: parent.height + Style.space(10) + root.audioPeak * Style.space(8)
      radius: height / 2
      color: "transparent"
      border.color: root.micLive ? "#22c55e" : (root.sharingScreen ? "#3b82f6" : "#e06c75")
      border.width: Style.space(1)
      opacity: (pill.hovered ? 0.60 : 0.25) + 0.28 * Math.min(1.0, root.audioPeak * 2.0)
      Behavior on opacity {
        NumberAnimation { duration: 150 }
      }

      SequentialAnimation on scale {
        loops: Animation.Infinite
        running: root.active
        NumberAnimation { from: 0.98; to: 1.03; duration: 1100; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.03; to: 0.98; duration: 1100; easing.type: Easing.InOutSine }
      }
    }

    // Main dark frosted capsule background with drag support
    Rectangle {
      id: capsuleBg
      anchors.fill: parent
      radius: height / 2
      color: Util.alpha("#06090e", pill.hovered ? 0.97 : 0.87)
      border.color: root.micLive
        ? Util.alpha("#22c55e", pill.hovered ? 0.92 : 0.68)
        : (root.sharingScreen
          ? Util.alpha("#3b82f6", pill.hovered ? 0.92 : 0.68)
          : Util.alpha("#e06c75", pill.hovered ? 0.92 : 0.68))
      border.width: Style.space(1.5)

      Behavior on color {
        ColorAnimation { duration: 150 }
      }
      Behavior on border.color {
        ColorAnimation { duration: 150 }
      }

      MouseArea {
        id: dragArea
        anchors.fill: parent
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: pill
        drag.minimumX: Style.space(12)
        hoverEnabled: true
        drag.maximumX: root.width - pill.width - Style.space(12)
        drag.minimumY: Style.space(12)
        drag.maximumY: root.height - pill.height - Style.space(12)

        onPositionChanged: {
          if (drag.active) {
            pill.moved = true
            pill.customX = pill.x
            pill.customY = pill.y
          }
        }
      }
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(9)

      // Drag grip indicator
      Text {
        text: "󰇙"
        color: Util.alpha("#ffffff", 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }

      // Interactive Mic Button
      Rectangle {
        id: micBtn
        width: Style.space(32)
        height: width
        radius: width / 2
        color: root.micLive
          ? (micMouse.containsMouse ? Util.alpha("#15803d", 0.88) : Util.alpha("#22c55e", 0.72))
          : (micMouse.containsMouse ? Util.alpha("#b91c1c", 0.88) : Util.alpha("#e06c75", 0.72))
        anchors.verticalCenter: parent.verticalCenter
        scale: 1.0 + (root.micLive ? 0.15 * Math.min(1.0, root.audioPeak * 2.0) : 0)

        Behavior on scale {
          NumberAnimation { duration: 60 }
        }

        Text {
          anchors.centerIn: parent
          text: root.micLive ? "󰍬" : "󰍭"
          font.family: Style.font.family
          font.pixelSize: Style.space(17)
          color: "#ffffff"
        }

        MouseArea {
          id: micMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleMicRequested()
        }

        PanelToolTip {
          visible: micMouse.containsMouse
          text: root.micLive ? "Click to mute microphone" : "Click to unmute microphone"
          fontFamily: Style.font.family
        }
      }

      // Status text and audio wave
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Row {
          spacing: Style.space(5)
          anchors.left: parent.left

          Text {
            text: root.micLive ? "MIC OPEN" : "MUTED"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.1
            color: root.micLive ? "#22c55e" : "#e06c75"
          }

          Text {
            visible: root.channel !== ""
            text: "· " + root.channel
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Util.alpha("#ffffff", 0.75)
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }

        // Dynamic audio equalizer bars
        Row {
          spacing: Style.space(3)
          visible: root.micLive
          Repeater {
            model: 5
            Rectangle {
              readonly property real baseH: index === 2 ? 10 : (index % 2 === 1 ? 7 : 5)
              width: Style.space(3)
              height: Style.space(Math.max(3, baseH * (0.4 + root.audioPeak * 1.8)))
              radius: 1.5
              color: "#22c55e"
              anchors.verticalCenter: parent.verticalCenter

              Behavior on height {
                NumberAnimation { duration: 50 }
              }
            }
          }
        }
      }

      // Interactive Screenshare Indicator & Stop Button
      Rectangle {
        id: shareBtn
        visible: root.sharingScreen
        width: shareContent.implicitWidth + Style.space(14)
        height: Style.space(28)
        radius: height / 2
        color: shareMouse.containsMouse ? Util.alpha("#1d4ed8", 0.88) : Util.alpha("#2563eb", 0.72)
        anchors.verticalCenter: parent.verticalCenter

        Row {
          id: shareContent
          anchors.centerIn: parent
          spacing: Style.space(4)

          Text {
            text: "󰍹"
            font.family: Style.font.family
            font.pixelSize: Style.space(14)
            color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "STOP SHARE"
            font.family: Style.font.family
            font.pixelSize: Style.space(9)
            font.bold: true
            font.letterSpacing: 0.8
            color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          id: shareMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.stopShareRequested()
        }

        PanelToolTip {
          visible: shareMouse.containsMouse
          text: "Click to stop screen share (Focus Discord)"
          fontFamily: Style.font.family
        }
      }
    }
  }
}
