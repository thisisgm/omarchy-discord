import QtQuick
import Quickshell.Io
import "Model.js" as Model

// rpc.py owns Discord's binary socket and speaks one JSON object per line.
Item {
  id: root

  // Driven by Service: there is no socket to talk to unless Discord is running.
  property bool active: false

  readonly property int restartDelayMs: 4000
  // A bridge that cannot start stops being retried, rather than respawning python3 forever.
  readonly property int maxRestarts: 5
  property int restarts: 0
  // rpc.py exits 2 when no credentials exist, which no amount of retrying fixes.
  readonly property int exitUnconfigured: 2

  // Qt hands back a file:// URL and Process needs a plain path.
  readonly property string scriptPath: String(Qt.resolvedUrl("rpc.py")).replace("file://", "")

  property bool configured: true
  // Lets the bridge start while unconfigured, until it answers, so the panel keeps showing setup meanwhile.
  property bool probing: false
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

  // Not error === "": rpc.py warns on stderr about refusals it survives, and a warning is not a disconnect.
  readonly property bool connected: ready
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
    probing = true
    error = ""
    restarts = 0
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

  // lines look like {"ok":true,"channel":"General","guild":"GM's Server","mute":false,"deaf":false,"inputVolume":100,"speaking":["gm"],"error":"","ping":36,"voiceState":"VOICE_CONNECTED"}
  function applyLine(line) {
    var state = Model.parseRpcLine(line)
    if (!state) return

    if (state.ok === false) {
      // Only the unconfigured line says the tier can never work; any other error got past that check.
      root.configured = state.configured !== false
      root.probing = false
      root.error = String(state.error || "Discord RPC failed")
      root.ready = false
      return
    }

    root.error = ""
    root.configured = true
    root.probing = false
    root.channel = String(state.channel || "")
    root.guild = String(state.guild || "")
    root.mute = state.mute === true
    root.deaf = state.deaf === true
    root.inputVolume = Math.round(Number(state.inputVolume) || 0)
    root.speaking = state.speaking instanceof Array ? state.speaking : []
    root.ping = Math.round(Number(state.ping) || 0)
    root.voiceState = String(state.voiceState || "")
    root.ready = true
    root.restarts = 0
  }

  // Blocks the next start: one delay after a crash, or until retry() once the budget is spent.
  property bool holdOff: false

  // A fresh Discord is a fresh chance, so no failure state outlives the process it belonged to.
  onActiveChanged: if (!active) {
    holdOff = false
    restarts = 0
    error = ""
  }

  Process {
    id: bridge
    running: root.active && (root.configured || root.probing) && !root.holdOff
    command: ["python3", root.scriptPath]
    stdinEnabled: true

    stdout: SplitParser {
      onRead: function (line) { root.applyLine(line) }
    }

    // Fatal failures arrive as JSON on stdout, so a line here is a warning worth showing.
    stderr: SplitParser {
      onRead: function (line) {
        var text = String(line).trim()
        if (text !== "") root.error = text
      }
    }

    onRunningChanged: if (!running) root.clear()

    onExited: function (exitCode) {
      // Discord quitting takes the bridge with it, and that is not a failure to count.
      if (!root.active || exitCode === root.exitUnconfigured) return
      root.holdOff = true
      root.restarts += 1
      // Past the budget the hold stays until retry() or the next Discord lifts it.
      if (root.restarts > root.maxRestarts) {
        root.error = "Discord voice bridge keeps failing, see the shell log"
        return
      }
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: root.restartDelayMs
    onTriggered: root.holdOff = false
  }
}
