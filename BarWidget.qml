import QtQuick
import qs.Commons
import qs.Ui

// Static launcher only. The persistent panel remains the single owner of the
// Frotz process and game session.
Panel {
  id: root
  moduleName: "jobo.lantern"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    tooltipText: "Lantern"
    fixedWidth: root.bar && root.bar.vertical ? -1 : Style.space(27)
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.LeftButton)
        root.bar.run("omarchy-shell shell toggle jobo.lantern '{}'")
    }

    Image {
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      source: Qt.resolvedUrl("assets/lantern.svg")
      sourceSize: Qt.size(64, 64)
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }
  }
}
