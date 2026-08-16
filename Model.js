// Pure helpers for the Discord widget: matching, parsing, formatting.
// Nothing here creates QML objects or has side effects, so every function is
// safe to call from a property binding.

var KIB_PER_MIB = 1024
var MIB_PER_GIB = 1024

// ---------------------------------------------------------------- desktop

// The discord package's desktop entry sets StartupWMClass=discord; Quickshell
// 0.3 exposes that as startupClass but exposes no entry id to match instead.
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

// Hyprland raises urgency when a client asks for attention through
// xdg-activation, which is what Discord does on a mention or a DM.
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

// Observed live: Discord's streams carry application.name "WEBRTC VoiceEngine",
// so the process binary is the only field that names the app.
function isOwnedByDiscord(node) {
  return String(nodeProps(node)["application.process.binary"] || "") === "Discord"
}

// The voice engine only holds streams while connected to a call, which makes
// them the call indicator; ordinary notification sounds do not use it.
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

// A playback stream feeds a sink, so PipeWire publishes it with isSink true;
// capture streams publish as stream sources. Same test the audio panel uses.
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
// The main process is the one with no --type=; its siblings are renderers,
// GPU, and utility children, and signalling those only files a crash report.
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

// ---------------------------------------------------------------- format

function formatMemory(mib) {
  if (!(mib > 0)) return "—"
  if (mib >= MIB_PER_GIB) return (mib / MIB_PER_GIB).toFixed(1) + " GiB"
  return Math.round(mib) + " MiB"
}

function formatFootprint(mib, count) {
  if (!(count > 0)) return "—"
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
