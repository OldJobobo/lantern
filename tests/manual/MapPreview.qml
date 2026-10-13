import QtQuick
import "../.." as Lantern

Window {
  id: preview
  property real previewScale: 1.0
  property bool captureMode: Qt.application.arguments.indexOf("--capture") !== -1
  property var denseState: ({
    schemaVersion: 1,
    cartridge: ({ engine: "zmachine", sha256: "1111111111111111111111111111111111111111111111111111111111111111" }),
    nodes: [
      { id: "room-1", label: "West of House", confidence: "confirmed", firstSeen: 1, lastSeen: 24 },
      { id: "room-2", label: "North of House", confidence: "confirmed", firstSeen: 2, lastSeen: 7 },
      { id: "room-3", label: "Behind House", confidence: "confirmed", firstSeen: 3, lastSeen: 9 },
      { id: "room-4", label: "South of House", confidence: "confirmed", firstSeen: 4, lastSeen: 4 },
      { id: "room-5", label: "Kitchen", confidence: "confirmed", firstSeen: 10, lastSeen: 14 },
      { id: "room-6", label: "Attic", confidence: "confirmed", firstSeen: 11, lastSeen: 11 },
      { id: "room-7", label: "Living Room", confidence: "confirmed", firstSeen: 15, lastSeen: 18 },
      { id: "room-8", label: "Cellar", confidence: "confirmed", firstSeen: 19, lastSeen: 20 },
      { id: "room-9", label: "Forest Path", confidence: "confirmed", firstSeen: 21, lastSeen: 23 },
      { id: "room-10", label: "Maze", confidence: "confirmed", firstSeen: 25, lastSeen: 31 },
      { id: "room-11", label: "Maze", confidence: "confirmed", firstSeen: 26, lastSeen: 30 },
      { id: "room-12", label: "Rocky Clearing", confidence: "confirmed", firstSeen: 32, lastSeen: 32 },
      { id: "room-13", label: "Deep Canyon", confidence: "confirmed", firstSeen: 33, lastSeen: 35 },
      { id: "room-14", label: "Ruined Temple", confidence: "confirmed", firstSeen: 36, lastSeen: 36 },
      { id: "room-15", label: "Vertical Shaft", confidence: "confirmed", firstSeen: 37, lastSeen: 38 },
      { id: "room-16", label: "Echo Chamber (Unplaced)", confidence: "confirmed", firstSeen: 39, lastSeen: 39 }
    ],
    edges: [
      { from: "room-1", to: "room-2", direction: "north", command: "north", confirmed: true, traversals: 3 },
      { from: "room-2", to: "room-1", direction: "south", command: "south", confirmed: true, traversals: 2 },
      { from: "room-2", to: "room-3", direction: "east", command: "east", confirmed: true, traversals: 2 },
      { from: "room-3", to: "room-4", direction: "south", command: "south", confirmed: true, traversals: 1 },
      { from: "room-4", to: "room-1", direction: "west", command: "west", confirmed: true, traversals: 1 },
      { from: "room-3", to: "room-5", direction: "in", command: "in", confirmed: true, traversals: 2 },
      { from: "room-5", to: "room-3", direction: "out", command: "out", confirmed: true, traversals: 1 },
      { from: "room-5", to: "room-6", direction: "up", command: "up", confirmed: true, traversals: 1 },
      { from: "room-6", to: "room-5", direction: "down", command: "down", confirmed: true, traversals: 1 },
      { from: "room-5", to: "room-7", direction: "west", command: "west", confirmed: true, traversals: 3 },
      { from: "room-7", to: "room-8", direction: "down", command: "down", confirmed: true, traversals: 1 },
      { from: "room-3", to: "room-9", direction: "east", command: "east", confirmed: true, traversals: 1 },
      { from: "room-9", to: "room-12", direction: "north", command: "north", confirmed: true, traversals: 1 },
      { from: "room-12", to: "room-13", direction: "southeast", command: "southeast", confirmed: true, traversals: 1 },
      { from: "room-13", to: "room-14", direction: "southwest", command: "southwest", confirmed: true, traversals: 1 },
      { from: "room-14", to: "room-15", direction: "up", command: "up", confirmed: true, traversals: 1 },
      { from: "room-10", to: "room-10", direction: "north", command: "north", confirmed: true, traversals: 2 },
      { from: "room-10", to: "room-11", direction: "east", command: "east", confirmed: true, traversals: 1 },
      { from: "room-10", to: "room-11", direction: "northeast", command: "northeast", confirmed: true, traversals: 1 },
      { from: "room-11", to: "room-10", direction: "west", command: "west", confirmed: true, traversals: 1 },
      { from: "room-8", to: "room-10", direction: "south", command: "south", confirmed: true, traversals: 1 },
      { from: "room-15", to: "room-16", direction: "in", command: "in", confirmed: true, traversals: 1 }
    ],
    layout: ({
      seed: 18273,
      positions: ({
        "room-1": { x: 0, y: 0, z: 0 },
        "room-2": { x: 0, y: -1, z: 0 },
        "room-3": { x: 1, y: -1, z: 0 },
        "room-4": { x: 1, y: 0, z: 0 },
        "room-5": { x: 1, y: -1, z: 1 },
        "room-6": { x: 1, y: -1, z: 2 },
        "room-7": { x: 0, y: -1, z: 1 },
        "room-8": { x: 0, y: -1, z: 0 },
        "room-9": { x: 2, y: -1, z: 0 },
        "room-10": { x: -1, y: 1, z: -1 },
        "room-11": { x: -1, y: 1, z: -1 },
        "room-12": { x: 2, y: -2, z: 0 },
        "room-13": { x: 3, y: -1, z: 0 },
        "room-14": { x: 2, y: 0, z: 0 },
        "room-15": { x: 2, y: 0, z: 1 }
      })
    }),
    currentNodeId: null,
    candidateNodeIds: [],
    resyncRequired: false,
    turn: 39
  })

  width: Math.round(1020 * previewScale)
  height: Math.round(765 * previewScale)
  minimumWidth: width
  minimumHeight: height
  maximumWidth: width
  maximumHeight: height
  visible: true
  color: "#151611"
  title: "Lantern Map Component Preview"

  Item {
    id: logicalSurface
    width: 1020
    height: 765
    scale: preview.previewScale
    transformOrigin: Item.TopLeft
    focus: true

    Rectangle {
      anchors.fill: parent
      color: "#171812"

      Rectangle {
        x: 88; y: 58; width: 844; height: 604; radius: 22
        color: "#07100c"
        border.width: 9
        border.color: "#292b25"
      }
      Text {
        anchors.centerIn: parent
        text: "CRT TRANSCRIPT CONTINUES BEHIND THE PAPER\n\nCTRL+P MAP  ·  R REDUCED MOTION  ·  1/2/3 SCALE"
        horizontalAlignment: Text.AlignHCenter
        color: "#5f9971"
        opacity: 0.7
        font.family: "monospace"
        font.pixelSize: 13
        textFormat: Text.PlainText
      }
    }

    Lantern.MapOverlay {
      id: mapOverlay
      mapState: preview.denseState
      currentNodeId: "room-13"
      sessionKey: "zmachine-preview"
      available: true
      renderScale: preview.previewScale
    }

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
        if (!event.isAutoRepeat) mapOverlay.toggleMap(true)
        event.accepted = true
      } else if (event.key === Qt.Key_R) {
        mapOverlay.reduceMotion = !mapOverlay.reduceMotion
        event.accepted = true
      } else if (event.key === Qt.Key_1 || event.key === Qt.Key_2 || event.key === Qt.Key_3) {
        preview.previewScale = event.key === Qt.Key_1 ? 1.0 : event.key === Qt.Key_2 ? 1.25 : 1.5
        event.accepted = true
      }
    }
  }

  Timer {
    interval: 80
    running: preview.captureMode
    repeat: false
    onTriggered: mapOverlay.openMap(false)
  }

  Timer {
    interval: 1050
    running: preview.captureMode
    repeat: false
    onTriggered: {
      logicalSurface.grabToImage(function(result) {
        var destination = decodeURIComponent(String(Qt.resolvedUrl("../../assets/map-preview.png"))).replace(/^file:\/\//, "")
        if (!result.saveToFile(destination)) console.error("capture failed")
        Qt.quit()
      }, Qt.size(1020, 765))
    }
  }
}
