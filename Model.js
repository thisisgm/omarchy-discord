// Pure helpers: no QML objects, no side effects, safe from a property binding.

var KIB_PER_MIB = 1024
var MIB_PER_GIB = 1024

// ---------------------------------------------------------------- desktop

// Quickshell 0.3 exposes StartupWMClass as startupClass and no entry id to match.
function findEntry(applications) {
  var list = applications || []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (entry && String(entry.startupClass || "").toLowerCase() === "discord") return entry
  }
  return null
}

// ---------------------------------------------------------------- windows

function toplevelClass(toplevel) {
  if (!toplevel) return ""
  // The Wayland handle carries the app id; the IPC snapshot is the fallback.
  var wayland = toplevel.wayland
  if (wayland && wayland.appId) return String(wayland.appId)
  var ipc = toplevel.lastIpcObject
  return ipc ? String(ipc["class"] || ipc["initialClass"] || "") : ""
}

// hyprctl reports both class and initialClass as exactly "discord" here.
function matchWindows(toplevels) {
  var list = toplevels || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (String(toplevelClass(list[i])).toLowerCase() === "discord") out.push(list[i])
  }
  return out
}

// Hyprland raises urgency from xdg-activation, which Discord uses for a mention.
function anyUrgent(windows) {
  var list = windows || []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].urgent === true) return true
  }
  return false
}

function workspaceLabel(toplevel) {
  var workspace = toplevel ? toplevel.workspace : null
  if (!workspace) return ""
  var name = String(workspace.name || "")
  if (name !== "") return name
  return workspace.id === undefined ? "" : String(workspace.id)
}

// ---------------------------------------------------------------- pipewire

// PwNode.properties is only valid once a PwObjectTracker has bound the node.
function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function streamNodes(nodes) {
  var list = nodes || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].isStream) out.push(list[i])
  }
  return out
}

// Streams say "WEBRTC VoiceEngine", so the process binary alone names the app.
function isOwnedByDiscord(node) {
  return String(nodeProps(node)["application.process.binary"] || "") === "Discord"
}

// The voice engine holds streams only while in a call; notification sounds do not.
function isVoiceStream(node) {
  return isOwnedByDiscord(node) && String(nodeProps(node)["application.name"] || "") === "WEBRTC VoiceEngine"
}

function hasVoiceStream(nodes) {
  var list = nodes || []
  for (var i = 0; i < list.length; i++) {
    if (isVoiceStream(list[i])) return true
  }
  return false
}

// A playback stream publishes with isSink true, the same test the audio panel uses.
function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true
  return String(node.type || "").indexOf("Output") !== -1
}

function findDiscordStream(nodes, playback) {
  var list = nodes || []
  for (var i = 0; i < list.length; i++) {
    var node = list[i]
    if (!node || !node.audio) continue
    if (isPlaybackStream(node) !== playback) continue
    if (isOwnedByDiscord(node)) return node
  }
  return null
}

// ---------------------------------------------------------------- process

// lines look like "239958 272772 /home/gm/.config/discord/app-1.0.154/Discord --type=renderer"
// The main process is the one with no --type=; signalling a child files a crash report.
function parseProcesses(raw) {
  var lines = String(raw || "").split("\n")
  var count = 0
  var rssKib = 0
  var mainPid = 0

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue

    var fields = line.split(/\s+/)
    var pid = parseInt(fields[0], 10)
    var rss = parseInt(fields[1], 10)
    if (!isFinite(pid) || !isFinite(rss)) continue

    count += 1
    rssKib += rss
    if (mainPid === 0 && fields.slice(2).join(" ").indexOf("--type=") === -1) mainPid = pid
  }

  return { count: count, memoryMib: rssKib / KIB_PER_MIB, mainPid: mainPid }
}

// -------------------------------------------------------------------- rpc

// lines look like {"ok":true,"channel":"General","guild":"GM's Server","mute":false,"speaking":["gm"]}
function parseRpcLine(raw) {
  try {
    var state = JSON.parse(String(raw))
    return state && typeof state === "object" ? state : null
  } catch (error) {
    return null
  }
}

// "General" names half the voice channels in existence, so say whose it is.
function callPlace(channel, guild) {
  if (!channel) return ""
  return guild ? channel + " · " + guild : String(channel)
}

// ---------------------------------------------------------------- signal

// Omarchy has no green or yellow, so quality is glyph strength first (NOTES.md).
var PING_GOOD_MS = 100
var PING_FAIR_MS = 250

function pingQuality(ping, connected) {
  if (!connected) return "none"
  if (!(ping > 0)) return "unknown"
  if (ping <= PING_GOOD_MS) return "good"
  if (ping <= PING_FAIR_MS) return "fair"
  return "poor"
}

function pingGlyph(quality) {
  if (quality === "good") return "󰤨"
  if (quality === "fair") return "󰤢"
  if (quality === "poor") return "󰤟"
  return "󰤯"
}

// ---------------------------------------------------------------- format

function formatMemory(mib) {
  if (!(mib > 0)) return "--"
  if (mib >= MIB_PER_GIB) return (mib / MIB_PER_GIB).toFixed(1) + " GiB"
  return Math.round(mib) + " MiB"
}

// titles read "#general | GM's Server - Discord"; every one carries the suffix
function windowTitle(toplevel) {
  var title = toplevel && toplevel.title ? String(toplevel.title) : ""
  var suffix = " - Discord"
  if (title.length > suffix.length && title.slice(-suffix.length) === suffix) {
    title = title.slice(0, -suffix.length)
  }
  return title === "" ? "Discord" : title
}

function formatUsage(mib, count) {
  if (!(count > 0)) return "--"
  var processes = count === 1 ? "1 process" : count + " processes"
  return formatMemory(mib) + " · " + processes
}

// The line under the title in the panel hero, and the widget's tooltip.
function statusPhrase(service) {
  if (!service.installed) return "Not installed"
  if (!service.running) return "Not running"
  if (service.attention) return "Wants your attention"
  if (service.inVoice) {
    // The bridge knows which call; PipeWire only knows that there is one.
    var place = callPlace(service.callChannel, service.callGuild)
    if (place === "") return service.micLive ? "In a call" : "In a call · mic closed"
    return service.micLive ? place : place + " · muted"
  }
  if (!service.hasWindow) return "Running in the background"
  if (service.workspace !== "") return "Open on workspace " + service.workspace
  return "Running"
}
