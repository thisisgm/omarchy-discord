import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.thisisgm.discord"
  ipcTarget: "discord"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool hideWhenStopped: setting("hideWhenStopped", false) === true
  readonly property real volumeStep: 0.05
  // Discord's own input volume is a 0-100 percentage, not a PipeWire ratio.
  readonly property int gainStep: 5

  // Discord's own call controls exist only while the bridge is in a call.
  readonly property bool callControls: discord.rpc.inVoice

  // The mic row draws inside the voice section, so the cursor has to use the same test.
  readonly property bool micRowVisible: discord.hasMicControl && !callControls
    && (discord.inVoice || discord.hasPlayback)

  readonly property string pingQuality: Model.pingQuality(
    discord.rpc.ping, discord.rpc.voiceState === "VOICE_CONNECTED")

  // Must match REDIRECT_URI in rpc.py.
  readonly property string redirectUri: "http://localhost/omarchy-discord"

  readonly property bool setupVisible: discord.running && !discord.rpc.configured
  property bool setupOpen: false
  property string setupError: ""

  function submitSetup() {
    setupError = ""
    if (!saveProcess.running) saveProcess.running = true
  }

  // The form's fields are not cursor stops, so opening it has to hand focus over.
  function openSetup() {
    setupOpen = true
    setupId.forceActiveFocus()
  }

  function resetSetup() {
    setupOpen = false
    setupError = ""
    setupId.text = ""
    setupSecret.text = ""
  }

  readonly property string callSubtitle: {
    if (discord.rpc.deaf) return "Deafened"
    if (discord.micMuted) return "Muted"
    if (pingQuality === "poor" || pingQuality === "fair") return "Unstable · " + discord.rpc.ping + " ms"
    var talking = discord.rpc.speaking
    if (talking.length === 1) return talking[0] + " is talking"
    if (talking.length > 1) return talking.join(", ") + " are talking"
    return "Connected"
  }
  // The meter reads low at speech level, so scale it up to fill the bar.
  readonly property real peakScale: 1.6

  readonly property color barIconColor: discord.attention
    ? (bar ? bar.urgent : Color.urgent)
    : (discord.running ? barForeground : Qt.darker(barForeground, 1.6))

  property bool cursorActive: false
  property int rowIndex: 0

  // Cursor stops in draw order; rows look themselves up by kind, so nothing desyncs.
  readonly property var navRows: {
    var list = []
    if (discord.installed) list.push({ kind: "power" })
    if (callControls || micRowVisible) list.push({ kind: "mic" })
    if (callControls) list.push({ kind: "deafen" })
    if (callControls) list.push({ kind: "hangup" })
    if (callControls) list.push({ kind: "gain" })
    if (discord.hasPlayback) list.push({ kind: "volume" })
    if (setupVisible && !setupOpen) list.push({ kind: "setup" })
    for (var i = 0; i < discord.windows.length; i++) list.push({ kind: "window", windowIndex: i })
    // The window rows already focus Discord, so this row is only for when there is none.
    if (!discord.hasWindow) list.push({ kind: "open" })
    return list
  }

  readonly property var currentRow: rowIndex >= 0 && rowIndex < navRows.length ? navRows[rowIndex] : null

  function indexOfRow(kind, windowIndex) {
    for (var i = 0; i < navRows.length; i++) {
      var row = navRows[i]
      if (row.kind !== kind) continue
      if (kind === "window" && row.windowIndex !== windowIndex) continue
      return i
    }
    return -1
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy !== 0) {
      rowIndex = Math.max(0, Math.min(navRows.length - 1, rowIndex + dy))
      return
    }
    // Left and right stay on the row and adjust it, matching the audio panel.
    if (dx === 0 || !currentRow) return
    if (currentRow.kind === "volume") {
      discord.setAppVolume(discord.appVolume + (dx > 0 ? volumeStep : -volumeStep))
    } else if (currentRow.kind === "gain") {
      discord.setMicGain(discord.rpc.inputVolume + (dx > 0 ? gainStep : -gainStep))
    }
  }

  function setCursor(index) {
    cursorActive = true
    rowIndex = index
  }

  function activateCursor() {
    if (!currentRow) return
    switch (currentRow.kind) {
    case "power": discord.running ? discord.quit() : discord.launch(); break
    case "mic": discord.toggleMic(); break
    case "deafen": discord.toggleDeaf(); break
    case "hangup": discord.hangUp(); break
    case "volume": discord.toggleAppMute(); break
    case "window": discord.focusWindow(discord.windows[currentRow.windowIndex]); root.close(); break
    case "open": if (discord.installed) { discord.open(); root.close() } break
    case "setup": root.openSetup(); break
    }
  }

  visible: !hideWhenStopped || discord.running
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    rowIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    discord.refresh()
    discord.rpc.retry()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  } else {
    resetSetup()
  }

  Service {
    id: discord
  }

  // Shows audio actually reaching the call, not just that the mic is unmuted.
  PwNodePeakMonitor {
    id: micPeak
    node: discord.captureNode
    enabled: root.opened && discord.captureNode !== null
  }

  // raise and mute are the two worth binding a key to.
  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function raise(): string {
      if (!discord.installed) return "Discord is not installed"
      discord.open()
      return "ok"
    }
    // Discord answers the bridge asynchronously, so report the request, not the state.
    function mute(): string {
      if (!discord.hasMicControl) return "no microphone to mute"
      discord.toggleMic()
      return "ok"
    }
    function deafen(): string {
      if (!discord.voiceKnown) return "no voice bridge"
      discord.toggleDeaf()
      return "ok"
    }
    function hangup(): string {
      if (!discord.voiceKnown) return "no voice bridge"
      discord.hangUp()
      return "ok"
    }
  }

  Process {
    id: saveProcess
    command: ["python3", discord.rpc.scriptPath, "--save"]
    stdinEnabled: true

    onStarted: write(JSON.stringify({
      client_id: String(setupId.text).trim(),
      client_secret: String(setupSecret.text).trim()
    }) + "\n")

    stderr: SplitParser {
      onRead: function (line) {
        var text = String(line).trim()
        if (text !== "") root.setupError = text
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) return
      root.resetSetup()
      discord.rpc.retry()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: discord.attention
    tooltipText: "Discord: " + discord.statusText

    iconComponent: Component {
      Item {
        DiscordIcon {
          id: barIcon
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          opacity: discord.running ? 1.0 : 0.75
        }

        // Says connected, urgent when the call cannot hear you; the ring clears Clyde's leg.
        Rectangle {
          visible: discord.inVoice
          width: Style.space(6)
          height: width
          radius: width / 2
          color: root.bar ? root.bar.background : Color.background
          anchors.right: barIcon.right
          anchors.bottom: barIcon.bottom
          anchors.rightMargin: -Style.space(2)
          anchors.bottomMargin: -Style.space(1)

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(4)
            height: width
            radius: width / 2
            color: discord.micLive ? root.barForeground : root.urgent
          }
        }
      }
    }

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.MiddleButton) discord.open()
      else if (buttonCode === Qt.RightButton) discord.inVoice ? discord.toggleMic() : discord.refresh()
      else root.toggle()
    }

    onWheelMoved: function (delta) {
      if (discord.hasPlayback) discord.setAppVolume(discord.appVolume + (delta > 0 ? root.volumeStep : -root.volumeStep))
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) root.cursorActive = true
        else root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (root.setupOpen) return
        if (t === "o" || t === "O") { discord.open(); root.close() }
        else if (t === "m" || t === "M") discord.toggleMic()
        else if (t === "d" || t === "D") discord.toggleDeaf()
        else if (t === "r" || t === "R") discord.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

            // PanelHero is itself `id: root`, so inside its Components panel state comes through here.
            readonly property int navIndex: root.indexOfRow("power", -1)
            readonly property bool switchHasCursor: root.cursorActive && root.rowIndex === navIndex
            readonly property color heroIconColor: discord.attention ? root.urgent : root.foreground
            function focusSwitch() { root.setCursor(header.navIndex) }

          PanelHero {
            id: hero
            width: parent.width
            title: "Discord"
            meta: discord.statusText
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: discord.running ? 1.0 : 0.5

            iconComponent: Component {
              DiscordIcon {
                iconSize: Style.font.display
                color: header.heroIconColor
              }
            }

            // On means running; Discord is expensive enough that turning it off belongs here.
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: discord.installed
                checked: discord.running
                busy: discord.busy
                foreground: hero.foreground
                hasCursor: header.switchHasCursor
                onHovered: function (on) { if (on) header.focusSwitch() }
                onToggled: discord.running ? discord.quit() : discord.launch()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: discord.running ? "Quit Discord" : "Start Discord"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }
          }

          Text {
            // A bridge nobody set up is not an error, so it stays quiet until credentials exist.
            readonly property string message: discord.lastError !== ""
              ? discord.lastError
              : (discord.rpc.configured ? discord.rpc.error : "")

            visible: message !== ""
            width: parent.width
            text: message
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }

          InfoPair {
            visible: discord.running
            label: "RAM usage"
            value: Model.formatUsage(discord.memoryMib, discord.processCount)
          }

          PanelSeparator {
            visible: discord.inVoice || discord.hasPlayback
            foreground: root.foreground
          }

          Column {
            visible: discord.inVoice || discord.hasPlayback
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: discord.inVoice ? "VOICE CALL" : "AUDIO"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            CallRow {
              visible: root.callControls
              width: parent.width
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              // Only the fallback now: with the bridge up the call row owns the mic.
              MicRow {
                visible: root.micRowVisible
                width: parent.width
              }

              GainRow {
                visible: root.callControls
                width: parent.width
              }

              VolumeRow {
                visible: discord.hasPlayback
                width: parent.width
              }
            }
          }

          PanelSeparator {
            visible: root.setupVisible
            foreground: root.foreground
          }

          Column {
            visible: root.setupVisible
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "VOICE CONTROLS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              ActionRow {
                visible: !root.setupOpen
                width: parent.width
                kind: "setup"
                glyph: "󰒓"
                label: "Set up voice controls"
                sub: "Channel name, deafen and hang up"
                onTriggered: root.openSetup()
              }

              Column {
                id: setupForm
                visible: root.setupOpen
                width: parent.width
                spacing: Style.space(6)
                leftPadding: Style.space(10)
                rightPadding: Style.space(10)
                readonly property real fieldWidth: width - leftPadding - rightPadding

                Text {
                  width: setupForm.fieldWidth
                  text: "Create an application, add this redirect URI on its OAuth2 page, then paste the Client ID and Secret from that same page."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                // Meant to be read and copied, so it gets the readable size.
                Text {
                  width: setupForm.fieldWidth
                  text: root.redirectUri
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                TextField {
                  id: setupId
                  width: setupForm.fieldWidth
                  placeholderText: "Client ID"
                  foreground: root.foreground
                  font.family: root.fontFamily
                }

                TextField {
                  id: setupSecret
                  width: setupForm.fieldWidth
                  placeholderText: "Client Secret"
                  password: true
                  foreground: root.foreground
                  font.family: root.fontFamily
                }

                Text {
                  visible: root.setupError !== ""
                  width: setupForm.fieldWidth
                  text: root.setupError
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Row {
                  spacing: Style.space(6)

                  Button {
                    text: "Open portal"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: Util.execDetached("xdg-open " + Util.shellQuote("https://discord.com/developers/applications"))
                  }

                  Button {
                    text: "Connect"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.submitSetup()
                  }
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              visible: discord.hasWindow
              text: discord.windows.length > 1 ? "WINDOWS" : "WINDOW"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: actionColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: discord.windows

                WindowRow {
                  required property var modelData
                  required property int index
                  width: actionColumn.width
                  toplevel: modelData
                  windowIndex: index
                }
              }

              ActionRow {
                visible: !discord.hasWindow
                width: parent.width
                kind: "open"
                glyph: "󰍹"
                label: discord.running ? "Show Discord" : "Start Discord"
                actionEnabled: discord.installed
                onTriggered: { discord.open(); root.close() }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ components

  // Dropbox's label/value pair, on a RowLayout instead of a hand-measured spacer.
  component InfoPair: RowLayout {
    id: infoPair
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      text: infoPair.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      Layout.fillWidth: true
      text: infoPair.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }

  // Discord's own layout: call named on the left, mute/deafen/hang-up as icons on the right.
  component CallRow: Item {
    implicitHeight: callContent.implicitHeight + Style.spacing.rowPaddingX

    RowLayout {
      id: callContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: Model.pingGlyph(root.pingQuality)
        color: root.pingQuality === "poor" ? root.urgent
          : (root.pingQuality === "good" ? root.foreground : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(3)

        Text {
          Layout.fillWidth: true
          text: Model.callPlace(discord.callChannel, discord.callGuild)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.callSubtitle
          color: discord.rpc.deaf || discord.micMuted ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        // Discord draws a waveform here; this is the same thing, measured.
        Rectangle {
          Layout.fillWidth: true
          height: Style.space(3)
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          color: Util.alpha(root.foreground, 0.15)

          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, micPeak.peak * root.peakScale))
            height: parent.height
            radius: parent.radius
            color: discord.micMuted ? root.urgent : root.foreground
            opacity: discord.micMuted ? 0.4 : 0.9

            Behavior on width {
              NumberAnimation { duration: 90 }
            }
          }
        }
      }


      CallButton {
        kind: "mic"
        iconText: discord.micMuted ? "󰍭" : "󰍬"
        tooltipText: discord.micMuted ? "Unmute" : "Mute"
        foreground: discord.micMuted ? root.urgent : root.foreground
        onClicked: discord.toggleMic()
      }

      CallButton {
        kind: "deafen"
        iconText: discord.rpc.deaf ? "󰟎" : "󰋋"
        tooltipText: discord.rpc.deaf ? "Undeafen" : "Deafen"
        foreground: discord.rpc.deaf ? root.urgent : root.foreground
        onClicked: discord.toggleDeaf()
      }

      CallButton {
        kind: "hangup"
        iconText: "󰏵"
        tooltipText: "Leave call"
        hoverColor: root.urgent
        onClicked: discord.hangUp()
      }
    }
  }

  // A call button is its own cursor stop, so j/k walks the icons.
  component CallButton: PanelActionButton {
    property string kind: ""
    readonly property int navIndex: root.indexOfRow(kind, -1)

    fontFamily: root.fontFamily
    foreground: root.foreground
    bordered: true
    hasCursor: root.cursorActive && root.rowIndex === navIndex
    onHovered: function (on) { if (on) root.setCursor(navIndex) }
    Layout.alignment: Qt.AlignVCenter
  }

  component MicRow: CursorSurface {
    id: micRow
    readonly property int navIndex: root.indexOfRow("mic", -1)

    hasCursor: root.cursorActive && root.rowIndex === navIndex
    foreground: root.foreground
    implicitHeight: micContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(micRow.navIndex)
      onClicked: discord.toggleMic()
    }

    RowLayout {
      id: micContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: discord.micMuted ? "󰍭" : "󰍬"
        color: discord.micMuted ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(3)

        Text {
          Layout.fillWidth: true
          text: discord.micMuted ? "Microphone muted" : "Microphone live"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Rectangle {
          Layout.fillWidth: true
          height: Style.space(3)
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          color: Util.alpha(root.foreground, 0.15)

          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, micPeak.peak * root.peakScale))
            height: parent.height
            radius: parent.radius
            color: discord.micMuted ? root.urgent : root.foreground
            opacity: discord.micMuted ? 0.4 : 0.9

            Behavior on width {
              NumberAnimation { duration: 90 }
            }
          }
        }
      }

      ToggleSwitch {
        checked: !discord.micMuted
        foreground: root.foreground
        hasCursor: micRow.hasCursor
        onToggled: discord.toggleMic()
        onHovered: function (on) { if (on) root.setCursor(micRow.navIndex) }
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component VolumeRow: CursorSurface {
    id: volumeRow
    readonly property int navIndex: root.indexOfRow("volume", -1)

    hasCursor: root.cursorActive && root.rowIndex === navIndex
    foreground: root.foreground
    implicitHeight: volumeContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: root.setCursor(volumeRow.navIndex)
    }

    RowLayout {
      id: volumeContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: discord.appMuted ? "󰝟" : "󰕾"
        color: discord.appMuted ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: discord.toggleAppMute()
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(3)

        Text {
          Layout.fillWidth: true
          text: "Discord volume"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        PanelSlider {
          Layout.fillWidth: true
          bar: root.bar
          value: discord.appVolume
          minimum: 0
          maximum: discord.maxVolume
          step: root.volumeStep
          onMoved: function (v) { discord.setAppVolume(v) }
        }
      }

      Text {
        text: Math.round(discord.appVolume * 100) + "%"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component GainRow: CursorSurface {
    id: gainRow
    readonly property int navIndex: root.indexOfRow("gain", -1)

    hasCursor: root.cursorActive && root.rowIndex === navIndex
    foreground: root.foreground
    implicitHeight: gainContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: root.setCursor(gainRow.navIndex)
    }

    RowLayout {
      id: gainContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰘮"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(3)

        Text {
          Layout.fillWidth: true
          text: "Mic gain"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        PanelSlider {
          Layout.fillWidth: true
          bar: root.bar
          value: discord.rpc.inputVolume
          minimum: 0
          maximum: 100
          step: root.gainStep
          onMoved: function (v) { discord.setMicGain(v) }
        }
      }

      Text {
        text: discord.rpc.inputVolume + "%"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component WindowRow: CursorSurface {
    id: windowRow
    property var toplevel: null
    property int windowIndex: 0
    readonly property int navIndex: root.indexOfRow("window", windowIndex)
    readonly property bool wantsAttention: toplevel !== null && toplevel.urgent === true

    hasCursor: root.cursorActive && root.rowIndex === navIndex
    foreground: root.foreground
    implicitHeight: windowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(windowRow.navIndex)
      onClicked: {
        discord.focusWindow(windowRow.toplevel)
        root.close()
      }
    }

    RowLayout {
      id: windowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰍹"
        color: windowRow.wantsAttention ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: Model.windowTitle(windowRow.toplevel)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: {
            var workspace = Model.workspaceLabel(windowRow.toplevel)
            var where = workspace === "" ? "Open" : "Workspace " + workspace
            return windowRow.wantsAttention ? where + " · wants attention" : where
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property string kind: ""
    property string glyph: ""
    property string label: ""
    property string sub: ""
    property bool actionEnabled: true
    readonly property int navIndex: root.indexOfRow(kind, -1)

    signal triggered()

    hasCursor: root.cursorActive && root.rowIndex === navIndex
    foreground: root.foreground
    opacity: actionEnabled ? 1.0 : 0.5
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: actionRow.actionEnabled
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(actionRow.navIndex)
      onClicked: actionRow.triggered()
    }

    RowLayout {
      id: actionContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: actionRow.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: actionRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          visible: actionRow.sub !== ""
          text: actionRow.sub
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
