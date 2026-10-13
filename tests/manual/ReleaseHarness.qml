import QtQuick
import Quickshell
import "../.." as Lantern

ShellRoot {
  id: harness
  property int stage: 0
  property int ticks: 0
  property int initialTurn: 0
  property bool failed: false

  function fail(message) {
    failed = true
    console.error("LANTERN_HARNESS_FAIL: " + message + "\n" + panel.transcript + "\n" + panel.fileActionMessage)
    Qt.quit()
  }

  Lantern.Panel { id: panel }
  Component.onCompleted: {
    panel.audioMuted = true
    panel.reduceMotion = true
    panel.open(JSON.stringify({ cartridge: "zork1", effects: false }))
  }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      harness.ticks++
      if (harness.ticks > 300) { harness.fail("timeout stage " + harness.stage + ": " + panel.statusText); return }
      if (harness.stage === 0 && panel.mapAvailable) {
        panel.submitCommand("north")
        harness.stage = 1
      } else if (harness.stage === 1 && panel.mapState.edges.length === 1) {
        harness.initialTurn = panel.mapState.turn
        panel.window.setCommandDraft("look")
        panel.toggleMap(true)
        if (!panel.mapModal()) { harness.fail("map did not open"); return }
        harness.stage = 2
      } else if (harness.stage === 2) {
        if (panel.mapState.turn !== harness.initialTurn) { harness.fail("map consumed a turn"); return }
        panel.forceMapClosed()
        panel.submitCommand("save harness")
        harness.stage = 20
      } else if (harness.stage === 20 && panel.matchingSaveFileName("harness") !== "" && panel.transcript.indexOf("Ok.") !== -1) {
        panel.submitCommand("restore harness")
        harness.stage = 21
      } else if (harness.stage === 21 && panel.fileActionMode === "" && panel.mapState.resyncRequired === false && panel.mapObserverReady) {
        panel.returnToMenu()
        harness.stage = 3
      } else if (harness.stage === 3 && panel.viewMode === "menu" && !panel.mapFinalizationPending) {
        panel.launchCartridge(panel.bundledGames[0])
        harness.stage = 4
      } else if (harness.stage === 4 && panel.mapAvailable) {
        if (panel.mapState.edges.length !== 1) { harness.fail("map did not survive cartridge restart"); return }
        panel.returnToMenu()
        harness.stage = 5
      } else if (harness.stage === 5 && panel.viewMode === "menu" && !panel.mapFinalizationPending) {
        panel.launchCartridge(panel.bundledGames[1])
        harness.stage = 6
      } else if (harness.stage === 6 && panel.storyActivity() === "active" && panel.transcript.indexOf("ZORK II") !== -1) {
        if (panel.mapAvailable) { harness.fail("unproven cartridge enabled automap"); return }
        panel.returnToMenu()
        harness.stage = 7
      } else if (harness.stage === 7 && panel.viewMode === "menu" && !panel.mapFinalizationPending) {
        panel.launchCartridge(panel.adventureCartridge)
        harness.stage = 8
      } else if (harness.stage === 8 && panel.transcript.indexOf("Welcome to Adventure") !== -1) {
        if (panel.mapAvailable || panel.supportsMemoryBank) { harness.fail("Adventure feature availability"); return }
        panel.submitCommand("n")
        panel.submitCommand("east")
        harness.stage = 80
      } else if (harness.stage === 80 && panel.transcript.indexOf("You are inside a building") !== -1) {
        panel.returnToMenu()
        harness.stage = 9
      } else if (harness.stage === 9 && panel.viewMode === "menu") {
        panel.launchCartridge({ id: "minimal-scott", engine: "scottfree", title: "SCOTT FIXTURE",
          path: panel.cartridgeRoot + "/minimal-scott.dat", runtime: panel.scottFreeRuntimePath,
          source: "imported", saveMode: "scottfree" })
        harness.stage = 10
      } else if (harness.stage === 10 && panel.transcript.indexOf("Lantern Test Chamber") !== -1) {
        if (panel.mapAvailable || !panel.supportsMemoryBank) { harness.fail("ScottFree feature availability"); return }
        panel.submitCommand("save harness")
        harness.stage = 11
      } else if (harness.stage === 11 && panel.matchingSaveFileName("harness") !== "" && panel.transcript.indexOf("Saved.") !== -1) {
        panel.submitCommand("restore harness")
        harness.stage = 12
      } else if (harness.stage === 12 && panel.fileActionMode === "" && panel.transcript.indexOf("[LOADING  harness.sav]") !== -1) {
        panel.returnToMenu()
        harness.stage = 13
      } else if (harness.stage === 13 && panel.viewMode === "menu") {
        console.log("LANTERN_HARNESS_PASS")
        Qt.quit()
      }
    }
  }
}
