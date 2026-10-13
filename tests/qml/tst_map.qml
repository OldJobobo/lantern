import QtQuick
import QtTest
import "../.." as Lantern
import "../../Automap.js" as Automap

TestCase {
  id: testCase
  name: "PaperMapBehavior"
  width: 1020
  height: 765
  when: windowShown

  TextInput { id: command; text: "open window"; focus: true }
  Lantern.MapOverlay {
    id: overlay
    mapState: Automap.createEmptyState({ engine: "zmachine", sha256: "1".repeat(64) })
    sessionKey: "zork-test"
    onFocusRestoreRequested: function(item) { if (item) item.forceActiveFocus() }
  }
  Lantern.PaperSound { id: audio; playbackEnabled: false }
  SignalSpy { id: sounds; target: overlay; signalName: "transitionSoundRequested" }
  SignalSpy { id: restores; target: overlay; signalName: "focusRestoreRequested" }
  SignalSpy { id: playback; target: audio; signalName: "playbackRequested" }

  function init() {
    overlay.forceClosed()
    overlay.available = true
    overlay.reduceMotion = true
    audio.muted = false
    audio.reduceMotion = false
    audio.volume = 0.18
    command.forceActiveFocus()
    sounds.clear(); restores.clear(); playback.clear()
  }

  function test_escapeRestoresDraftAndFocus() {
    overlay.openMap(true)
    compare(overlay.motionState, "open")
    verify(overlay.modal)
    verify(!command.activeFocus)
    keyClick(Qt.Key_Escape)
    compare(overlay.motionState, "closed")
    compare(command.text, "open window")
    verify(command.activeFocus)
    compare(restores.count, 1)
    compare(sounds.count, 0, "reduced motion is silent")
  }

  function test_reversalAndForcedClosure() {
    overlay.reduceMotion = false
    overlay.openMap(true)
    compare(overlay.motionState, "opening")
    wait(100)
    overlay.closeMap(true)
    compare(overlay.motionState, "closing")
    wait(40)
    overlay.openMap(true)
    tryCompare(overlay, "motionState", "open", 1500)
    compare(sounds.count, 3)
    overlay.available = false
    compare(overlay.motionState, "closed")
    compare(sounds.count, 3, "availability loss never requests sound")
  }

  function test_scales_data() {
    return [{ tag: "1x", factor: 1.0 }, { tag: "1.25x", factor: 1.25 }, { tag: "1.5x", factor: 1.5 }]
  }

  function test_scales(data) {
    overlay.scale = data.factor
    overlay.renderScale = data.factor
    overlay.openMap(true)
    compare(overlay.motionState, "open")
    verify(overlay.accessibleSummary.length > 0)
    overlay.closeMap(true)
    compare(overlay.motionState, "closed")
    overlay.scale = 1.0
    overlay.renderScale = 1.0
  }

  function test_soundPolicyWithoutDevice() {
    audio.request("open"); compare(playback.count, 1)
    audio.request("close"); compare(playback.count, 2)
    audio.request("other"); compare(playback.count, 2)
    audio.muted = true; audio.request("open"); compare(playback.count, 2)
    audio.muted = false; audio.reduceMotion = true
    audio.request("close"); compare(playback.count, 2)
    audio.reduceMotion = false; audio.volume = 0
    audio.request("open"); compare(playback.count, 2)
  }
}
