import QtQuick
import Quickshell.Io
import "Model.js" as Model

// rpc.py owns Discord's binary socket and speaks one JSON object per line.
Item {
  id: root

  // Driven by Service: there is no socket to talk to unless Discord is running.
  property bool active: false

  readonly property int restartDelayMs: 4000
  // rpc.py exits 2 when no credentials exist, which no amount of retrying fixes.
  readonly property int exitUnconfigured: 2

  // Qt hands back a file:// URL and Process needs a plain path.
  readonly property string scriptPath: String(Qt.resolvedUrl("rpc.py")).replace("file://", "")

  property bool configured: true
  property bool ready: false
  property string error: ""

  property string channel: ""
  property string guild: ""
  property bool mute: false
  property bool deaf: false
  property int inputVolume: 100
  property var speaking: []
  property int ping: 0
  property string voiceState: ""

  readonly property bool connected: ready && error === ""
  readonly property bool inVoice: connected && channel !== ""

  // Cleared while the bridge is down so the panel never shows a stale call.
  function clear() {
    ready = false
    channel = ""
    guild = ""
    speaking = []
    ping = 0
    voiceState = ""
  }

  // Setup happens while the shell runs, so opening the panel re-checks.
  function retry() {
    configured = true
    error = ""
    holdOff = false
  }

  function send(message) {
    if (!bridge.running) return
    bridge.write(JSON.stringify(message) + "\n")
  }

  function setMute(value) { send({ cmd: "mute", value: value === true }) }
  function setDeaf(value) { send({ cmd: "deaf", value: value === true }) }
  function setInputVolume(value) { send({ cmd: "inputVolume", value: Math.round(value) }) }
  function hangUp() { send({ cmd: "disconnect" }) }
  function refresh() { send({ cmd: "refresh" }) }

  function applyLine(line) {
    var state = Model.parseRpcLine(line)
    if (!state) return

    if (state.ok === false) {
      // The bridge says outright when it can never work, so stop rather than retry.
      if (state.configured === false) root.configured = false
      root.error = String(state.error || "Discord RPC failed")
      root.ready = false
      return
    }

    root.error = ""
    root.channel = String(state.channel || "")
    root.guild = String(state.guild || "")
    root.mute = state.mute === true
    root.deaf = state.deaf === true
    root.inputVolume = Math.round(Number(state.inputVolume) || 0)
    root.speaking = state.speaking instanceof Array ? state.speaking : []
    root.ping = Math.round(Number(state.ping) || 0)
    root.voiceState = String(state.voiceState || "")
    root.ready = true
  }

  // Held down for one delay after a crash so a failing bridge cannot hot-loop.
  property bool holdOff: false

  Process {
    id: bridge
    running: root.active && root.configured && !root.holdOff
    command: ["python3", root.scriptPath]
    stdinEnabled: true

    stdout: SplitParser {
      onRead: function (line) { root.applyLine(line) }
    }

    // The bridge reports its own failures as JSON, so stderr is a crash.
    stderr: SplitParser {
      onRead: function (line) {
        var text = String(line).trim()
        if (text !== "") root.error = text
      }
    }

    onRunningChanged: if (!running) root.clear()

    onExited: function (exitCode) {
      if (exitCode === root.exitUnconfigured) return
      root.holdOff = true
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: root.restartDelayMs
    onTriggered: root.holdOff = false
  }
}
