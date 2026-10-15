// Pure helpers: no QML objects, no side effects, safe from a property binding.

var KIB_PER_MIB = 1024
var MIB_PER_GIB = 1024
// The two supported clients: the discord package publishes discord/Discord, vesktop vesktop.
var APP_IDS = ["discord", "vesktop"]

function isAppId(value) {
  return APP_IDS.indexOf(String(value || "").toLowerCase()) !== -1
}

// ---------------------------------------------------------------- desktop

// Quickshell 0.3 exposes StartupWMClass as startupClass and no entry id to match.
// Desktop list order is arbitrary, so pick the client last seen running, then APP_IDS order.
function findEntry(applications, preferredId) {
  var list = applications || []
  var wanted = [isAppId(preferredId) ? String(preferredId).toLowerCase() : ""].concat(APP_IDS)
  for (var w = 0; w < wanted.length; w++) {
    if (wanted[w] === "") continue
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (entry && String(entry.startupClass || "").toLowerCase() === wanted[w]) return entry
    }
  }
  return null
}

// The app id of the client actually on screen, which is what disambiguates a later cold launch.
function runningClientId(toplevels) {
  var matched = matchWindows(toplevels)
  return matched.length > 0 ? String(toplevelClass(matched[0])).toLowerCase() : ""
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

// hyprctl reports class and initialClass as the client's own app id here.
function matchWindows(toplevels) {
  var list = toplevels || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (isAppId(toplevelClass(list[i]))) out.push(list[i])
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

function isVideoNode(node) {
  if (!node) return false
  var props = nodeProps(node)
  var mediaClass = String(props["media.class"] || "").toLowerCase()
  var mediaType = String(props["media.type"] || "").toLowerCase()
  return mediaClass.indexOf("video") !== -1 || mediaType === "video"
}

function streamNodes(nodes) {
  var list = nodes || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var n = list[i]
    if (!n) continue
    if (n.isStream || isAppId(n.name)) out.push(n)
  }
  return out
}

// Streams say "WEBRTC VoiceEngine" or process binary, native video streams use node.name or media.name.
function isOwnedByDiscord(node) {
  var props = nodeProps(node)
  return isAppId(props["application.process.binary"]) ||
         isAppId(props["node.name"]) ||
         isAppId(props["media.name"])
}
// vesktop names every stream vesktop, so a call is only its audio capture stream, never video or playback.
// Discord publishes five nodes in a call and only one is the mic, so the name alone is not enough.
function isVoiceStream(node) {
  if (!isOwnedByDiscord(node)) return false
  var name = String(nodeProps(node)["application.name"] || "").toLowerCase()
  if (name !== "webrtc voiceengine" && name !== "vesktop") return false
  return !!node.audio && !isPlaybackStream(node)
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
  return node.isSink === true
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
function isVideoStream(node) {
  if (!node || !node.ready) return false
  if (!isOwnedByDiscord(node)) return false
  if (isPlaybackStream(node)) return false
  var props = nodeProps(node)
  var mediaClass = String(props["media.class"] || "").toLowerCase()
  var mediaType = String(props["media.type"] || "").toLowerCase()
  var mediaRole = String(props["media.role"] || "").toLowerCase()
  var mediaName = String(props["media.name"] || "").toLowerCase()
  if (mediaClass.indexOf("video") !== -1 || mediaType === "video") return true
  if (mediaRole === "screen" || mediaRole === "screencast" || mediaName.indexOf("screencast") !== -1) return true
  return false
}

function findDiscordVideoStreams(nodes) {
  var list = nodes || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var node = list[i]
    if (isVideoStream(node)) out.push(node)
  }
  return out
}


// ---------------------------------------------------------------- process

// discord: "239958 272772 /home/gm/.config/discord/app-1.0.154/Discord --type=renderer"
// vesktop: "248461 384348 /usr/lib/vesktop/vesktop"
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
    var base = place === "" ? "In a call" : place
    if (service.sharingScreen) {
      return service.micLive ? base + " · sharing screen" : base + " · sharing screen · muted"
    }
    if (place === "") return service.micLive ? "In a call" : "In a call · mic closed"
    return service.micLive ? place : place + " · muted"
  }
  if (service.sharingScreen) return "Sharing screen"
  if (!service.hasWindow) return "Running in the background"
  if (service.workspace !== "") return "Open on workspace " + service.workspace
  return "Running"
}
