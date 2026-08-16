import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import "Model.js" as Model

// Discord's state, read from the services the shell already runs. See README
// for which service answers which question.
Item {
  id: root

  readonly property int pollIntervalMs: 20000
  readonly property int settleIntervalMs: 1500
  readonly property int settleTicks: 4
  readonly property real maxVolume: 1.5

  // ------------------------------------------------------------ installed

  readonly property var applications: DesktopEntries.applications ? DesktopEntries.applications.values : []
  readonly property bool installed: Model.findEntry(applications) !== null

  // ------------------------------------------------------------ processes

  property bool running: false
  property int processCount: 0
  property real memoryMib: 0
  property int mainPid: 0
  property string lastError: ""

  readonly property bool busy: statusProcess.running

  // ------------------------------------------------------------ windows

  readonly property var toplevels: Hyprland.toplevels ? Hyprland.toplevels.values : []
  readonly property var windows: Model.matchWindows(toplevels)
  readonly property bool hasWindow: windows.length > 0
  readonly property var primaryWindow: hasWindow ? windows[0] : null
  readonly property string workspace: Model.workspaceLabel(primaryWindow)

  // Only exists while Discord has a window; a tray-hidden instance has nothing
  // for the compositor to flag.
  readonly property bool attention: Model.anyUrgent(windows)

  // ------------------------------------------------------------ voice

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var streamNodes: Model.streamNodes(nodes)
  readonly property var captureNode: Model.findDiscordStream(streamNodes, false)
  readonly property var playbackNode: Model.findDiscordStream(streamNodes, true)

  // The voice engine holds streams only while connected to a call; the bridge
  // names the call outright when it is configured.
  readonly property bool inVoice: bridge.inVoice || Model.hasVoiceStream(streamNodes)
  readonly property bool hasPlayback: playbackNode !== null

  // Discord's own voice state, when a registered application is configured.
  // Every property below falls back to PipeWire when it is not.
  Rpc {
    id: bridge
    active: root.running
  }

  readonly property alias rpc: bridge
  readonly property bool voiceKnown: bridge.connected
  readonly property string callChannel: bridge.channel
  readonly property string callGuild: bridge.guild

  // Discord's own mute is the truth whenever the bridge is up. Without it the
  // capture stream is all there is, and Discord drops that stream while the
  // microphone is closed, so there is nothing to mute until it comes back.
  readonly property bool hasMicControl: voiceKnown || captureNode !== null
  readonly property bool micMuted: voiceKnown
    ? bridge.mute
    : (captureNode && captureNode.audio ? captureNode.audio.muted : false)
  readonly property bool micLive: hasMicControl && !micMuted
  readonly property real appVolume: playbackNode && playbackNode.audio ? playbackNode.audio.volume : 0
  readonly property bool appMuted: playbackNode && playbackNode.audio ? playbackNode.audio.muted : false

  readonly property string statusText: Model.statusPhrase(root)

  // Binding the nodes is what makes their properties readable at all.
  PwObjectTracker {
    objects: root.streamNodes
  }

  // ------------------------------------------------------------ actions

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function applyProcesses(raw) {
    var parsed = Model.parseProcesses(raw)
    running = parsed.count > 0
    processCount = parsed.count
    memoryMib = parsed.memoryMib
    mainPid = parsed.mainPid
  }

  // Same path the Omarchy launcher uses, so Discord lands in app-graphical.slice
  // instead of inheriting the compositor's service.
  function launch() {
    if (!installed) return
    Util.execDetached("uwsm-app -- gtk-launch discord.desktop")
    settle()
  }

  function focusWindow(toplevel) {
    var target = toplevel || primaryWindow
    if (!target || !target.address) return
    // focuswindow follows the window to its workspace.
    Hyprland.dispatch("focuswindow address:" + target.address)
  }

  // Re-running the desktop entry is what recovers an instance that closed to a
  // tray icon: Electron hands the launch to the running process, which unhides.
  function open() {
    if (hasWindow) focusWindow(primaryWindow)
    else launch()
  }

  function quit() {
    if (!running) return
    if (mainPid > 0) Util.execDetached("kill " + mainPid)
    else Util.execDetached("pkill -x Discord")
    settle()
  }

  // Discord's own mute when the bridge is up: it survives the mic closing and
  // shows in Discord's UI, neither of which muting a PipeWire stream does.
  function toggleMic() {
    if (voiceKnown) {
      bridge.setMute(!bridge.mute)
      return
    }
    if (captureNode && captureNode.audio) captureNode.audio.muted = !captureNode.audio.muted
  }

  function toggleDeaf() {
    if (voiceKnown) bridge.setDeaf(!bridge.deaf)
  }

  function hangUp() {
    if (voiceKnown) bridge.hangUp()
  }

  function setMicGain(value) {
    if (voiceKnown) bridge.setInputVolume(Math.max(0, Math.min(100, value)))
  }

  function toggleAppMute() {
    if (playbackNode && playbackNode.audio) playbackNode.audio.muted = !playbackNode.audio.muted
  }

  function setAppVolume(value) {
    if (playbackNode && playbackNode.audio) playbackNode.audio.volume = Math.max(0, Math.min(maxVolume, value))
  }

  // Electron takes seconds to start or exit, so re-poll a few times rather than
  // leaving the panel stale until the next interval.
  function settle() {
    settleTimer.ticks = 0
    settleTimer.restart()
  }

  Process {
    id: statusProcess
    running: false
    command: ["ps", "-C", "Discord", "-o", "pid=,rss=,args="]

    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
    }

    // ps exits 1 with no output when nothing matches, which is Discord not
    // running rather than a failure.
    onExited: function (exitCode) {
      if (exitCode === 0 || exitCode === 1) {
        root.applyProcesses(statusStdout.text)
        root.lastError = ""
      } else {
        root.lastError = String(statusStderr.text || "") || "Could not read Discord processes"
      }
    }
  }

  Timer {
    interval: root.pollIntervalMs
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: settleTimer
    property int ticks: 0
    interval: root.settleIntervalMs
    repeat: true
    running: false
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= root.settleTicks) settleTimer.running = false
    }
  }

  // A window appearing or closing changes what the poll would say.
  onHasWindowChanged: refresh()
}
