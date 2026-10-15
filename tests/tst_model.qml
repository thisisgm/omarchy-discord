import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Model"

  readonly property var discordEntry: ({ startupClass: "discord", id: "discord.desktop" })
  readonly property var vesktopEntry: ({ startupClass: "vesktop", id: "vesktop.desktop" })
  readonly property var strangerEntry: ({ startupClass: "slack", id: "slack.desktop" })
  // Most .desktop files carry no StartupWMClass, and production passes the whole list.
  readonly property var classlessEntry: ({ id: "gimp.desktop" })

  function test_findEntry_prefers_the_client_last_seen_running() {
    var both = [discordEntry, vesktopEntry]
    compare(Model.findEntry(both, "vesktop").id, "vesktop.desktop")
    compare(Model.findEntry(both, "discord").id, "discord.desktop")

    // Desktop list order must not decide it, so the reversed list answers the same.
    compare(Model.findEntry([vesktopEntry, discordEntry], "vesktop").id, "vesktop.desktop")
  }

  function test_findEntry_falls_back_to_APP_IDS_order_not_list_order() {
    // No preference and both installed: discord wins on every machine, either way round.
    compare(Model.findEntry([discordEntry, vesktopEntry], "").id, "discord.desktop")
    compare(Model.findEntry([vesktopEntry, discordEntry], "").id, "discord.desktop")
  }

  function test_findEntry_ignores_a_preference_outside_the_supported_set() {
    // The stranger must be IN the list, or the case passes whether or not the gate exists.
    compare(Model.findEntry([strangerEntry, vesktopEntry], "slack").id, "vesktop.desktop")
  }

  function test_findEntry_returns_null_when_no_client_is_installed() {
    compare(Model.findEntry([strangerEntry], ""), null)
    compare(Model.findEntry([], ""), null)
  }

  function test_findEntry_never_matches_an_entry_without_a_startup_class() {
    // The empty sentinel for an unsupported preference must not select these.
    compare(Model.findEntry([classlessEntry], "slack"), null)
    compare(Model.findEntry([classlessEntry, vesktopEntry], "slack").id, "vesktop.desktop")
  }

  function node(binary, appName, opts) {
    var o = opts || {}
    return {
      ready: true,
      isStream: true,
      isSink: o.sink === true,
      type: 0,
      audio: o.audio === false ? null : ({ muted: false }),
      properties: { "application.process.binary": binary, "application.name": appName }
    }
  }

  function test_isVoiceStream_accepts_the_discord_voice_engine() {
    verify(Model.isVoiceStream(node("Discord", "WEBRTC VoiceEngine", {})))
  }

  function test_isVoiceStream_rejects_a_discord_stream_that_is_not_the_voice_engine() {
    verify(!Model.isVoiceStream(node("Discord", "Chromium input", {})))
  }

  // Measured in a live call: Discord publishes five nodes, and three carry this same name.
  function test_isVoiceStream_rejects_the_discord_playback_and_non_audio_nodes() {
    verify(!Model.isVoiceStream(node("Discord", "WEBRTC VoiceEngine", { sink: true })))
    verify(!Model.isVoiceStream(node("Discord", "WEBRTC VoiceEngine", { audio: false })))
  }

  function test_isVoiceStream_accepts_only_a_vesktop_audio_capture_stream() {
    verify(Model.isVoiceStream(node("vesktop", "vesktop", {})))

    // A screenshare or camera stream is not playback either, so it must not read as a call.
    verify(!Model.isVoiceStream(node("vesktop", "vesktop", { audio: false })))

    // Playback is never a call.
    verify(!Model.isVoiceStream(node("vesktop", "vesktop", { sink: true })))
  }

  // The five nodes a live Discord call actually publishes, three sharing the same name.
  function test_hasVoiceStream_accepts_exactly_the_capture_node_of_a_real_call() {
    var call = [
      node("Discord", "WEBRTC VoiceEngine", {}),                 // 82, Stream/Input/Audio
      node("Discord", "WEBRTC VoiceEngine", { sink: true }),     // 74, Stream/Output/Audio
      node("Discord", "WEBRTC VoiceEngine", { audio: false }),   // 79, no media.class
      node("Discord", "WEBRTC VoiceEngine", { audio: false }),   // 83, no media.class
      node("Discord", "Chromium input", { audio: false })        // 84, no media.class
    ]
    verify(Model.hasVoiceStream(call))
    var accepted = 0
    for (var i = 0; i < call.length; i++) {
      if (Model.isVoiceStream(call[i])) accepted++
    }
    compare(accepted, 1)

    // The same set with the mic gone is not a call, which is what the widget must show.
    verify(!Model.hasVoiceStream(call.slice(1)))
  }

  function test_isVoiceStream_rejects_a_stream_owned_by_neither_client() {
    verify(!Model.isVoiceStream(node("slack", "vesktop", {})))
  }

  function test_isVoiceStream_rejects_a_node_the_tracker_has_not_bound_yet() {
    var unbound = node("vesktop", "vesktop", {})
    unbound.ready = false
    verify(!Model.isVoiceStream(unbound))
  }

  function test_isVideoStream_accepts_discord_video_stream() {
    var vNode = node("Discord", "WEBRTC VoiceEngine", { audio: false })
    vNode.properties["media.class"] = "Stream/Input/Video"
    verify(Model.isVideoStream(vNode))

    var screencastNode = node("vesktop", "vesktop", { audio: false })
    screencastNode.properties["media.name"] = "portal-screencast"
    verify(Model.isVideoStream(screencastNode))
  }

  function test_isVideoStream_rejects_audio_and_foreign_streams() {
    var aNode = node("Discord", "WEBRTC VoiceEngine", {})
    aNode.properties["media.class"] = "Stream/Input/Audio"
    verify(!Model.isVideoStream(aNode))

    var foreignVideo = node("obs", "obs", { audio: false })
    foreignVideo.properties["media.class"] = "Stream/Input/Video"
    verify(!Model.isVideoStream(foreignVideo))
  }
}
