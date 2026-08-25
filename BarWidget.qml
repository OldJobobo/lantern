import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Static launcher only. The persistent panel remains the single owner of the
// Frotz process and game session.
Panel {
  id: root
  moduleName: "jobo.lantern"
  manageIpc: false

  property bool storyActive: false
  property color themeYellow: "#e6c86e"
  property real glowLevel: 1.0
  property string themeColorsText: ""

  readonly property string pluginRoot: decodeURIComponent(String(Qt.resolvedUrl(".")))
    .replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string boundedFileReader: pluginRoot + "/bin/read-bounded-file"
  readonly property int boundedFileBytes: 65536
  readonly property string themeColorsPath:
    (Quickshell.env("HOME") || "/tmp") + "/.local/state/omarchy/current/theme/colors.toml"

  function refreshStoryActivity() {
    var host = bar && bar.shell ? bar.shell : null
    if (!host || typeof host.callIfLoaded !== "function") {
      storyActive = false
      return
    }
    storyActive = host.callIfLoaded(moduleName, "storyActivity", "") === "active"
  }

  function loadThemeYellow(raw) {
    var values = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*(yellow|color3|color9)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (match) values[match[1]] = match[2]
    }
    themeYellow = values.yellow || values.color3 || values.color9 || "#e6c86e"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.storyActive ? "Lantern · Story running" : "Lantern"
    fixedWidth: root.bar && root.bar.vertical ? -1 : Style.space(27)
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.LeftButton)
        root.bar.run("omarchy-shell shell toggle jobo.lantern '{}'")
    }

    Item {
      id: iconCanvas
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 0
      width: Style.space(14)
      height: Style.space(13)

      Image {
        id: iconSource
        anchors.fill: parent
        visible: false
        source: Qt.resolvedUrl("assets/lantern.svg")
        sourceSize: Qt.size(64, 64)
        fillMode: Image.Stretch
        smooth: true
        mipmap: true
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: iconSource
        source: iconSource
        colorization: 1.0
        colorizationColor: root.storyActive ? root.themeYellow : button.foreground
        brightness: root.storyActive ? 0.04 + 0.08 * root.glowLevel : 0
        shadowEnabled: root.storyActive
        shadowColor: root.themeYellow
        shadowBlur: 0.45
        shadowOpacity: root.storyActive ? 0.10 + 0.15 * root.glowLevel : 0
        opacity: root.storyActive ? 0.72 + 0.28 * root.glowLevel : 1.0
      }
    }

    Timer {
      interval: 400
      repeat: true
      running: true
      triggeredOnStart: true
      onTriggered: {
        root.refreshStoryActivity()
        if (!paletteReader.running) paletteReader.running = true
      }
    }

    Process {
      id: paletteReader
      command: [root.boundedFileReader, root.themeColorsPath]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var next = Model.boundedFileText(text, root.boundedFileBytes)
          if (next === root.themeColorsText) return
          root.themeColorsText = next
          root.loadThemeYellow(next)
        }
      }
    }

    Connections {
      target: Color
      function onForegroundChanged() {
        if (!paletteReader.running) paletteReader.running = true
      }
      function onShellValuesChanged() {
        if (!paletteReader.running) paletteReader.running = true
      }
    }

    SequentialAnimation {
      running: root.storyActive
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation {
        target: root
        property: "glowLevel"
        from: 0.35
        to: 1.0
        duration: 920
        easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: root
        property: "glowLevel"
        from: 1.0
        to: 0.35
        duration: 920
        easing.type: Easing.InOutSine
      }
    }
  }
}
