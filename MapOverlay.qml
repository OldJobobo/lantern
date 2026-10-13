import QtQuick
import QtQuick.Effects

Item {
  id: overlay

  // Standalone contract: the host owns availability, graph lifecycle,
  // persistence, and the exposed parent-window drag strip above this item.
  required property var mapState
  property string currentNodeId: ""
  property string sessionKey: ""
  property string mapTitle: "EXPLORER'S FIELD MAP"
  property bool available: true
  property bool reduceMotion: false
  property bool resetEnabled: true
  property string unavailableReason: "AUTOMAP IS NOT AVAILABLE FOR THIS CARTRIDGE"
  property real renderScale: 1.0
  property url paperSource: Qt.resolvedUrl("assets/old-graph-paper.png")
  property rect crtRect: Qt.rect(88, 58, 844, 604)
  property real dragStripHeight: 0

  readonly property string motionState: internalMotionState
  readonly property bool modal: internalMotionState !== "closed"
  readonly property string accessibleSummary: mapCanvas.accessibleSummary
  readonly property real logicalWidth: 1020
  readonly property real logicalHeight: 765
  readonly property real closedRotation: 0.9
  readonly property real openRotation: 1.4
  // Compatibility names retained for the standalone prototype.
  readonly property string transitionState: motionState
  readonly property bool mapOpen: motionState === "open"
  readonly property bool modalActive: modal
  property alias mapAvailable: overlay.available

  signal opening(bool userInitiated)
  signal opened(bool userInitiated)
  signal closing(bool userInitiated)
  signal closed(bool userInitiated)
  signal viewportChanged(string sessionKey, real panX, real panY, real zoom)
  signal resetMapRequested(string sessionKey)
  signal unavailableActivated(string reason)
  signal focusRestoreRequested(var priorItem)
  signal transitionSoundRequested(string kind)
  signal openRequested(bool userInitiated)
  signal closeRequested(bool userInitiated)
  signal eraseMapRequested()
  signal transitionStarted(string state, bool userInitiated)
  signal transitionFinished(string state, bool userInitiated)

  property string internalMotionState: "closed"
  property bool transitionUserInitiated: false
  property bool interruptTargetOpen: false
  property var viewportMemory: ({})
  property string activeSessionKey: ""
  property var priorFocusItem: null
  property bool eraseArmed: false

  width: logicalWidth
  height: logicalHeight
  z: 100
  focus: modal

  onSessionKeyChanged: switchViewportSession()
  onAvailableChanged: { if (!available) forceClosed() }
  onReduceMotionChanged: {
    if (reduceMotion && motionState === "opening") snapOpen(transitionUserInitiated)
    else if (reduceMotion && motionState === "closing") snapClosed(transitionUserInitiated)
  }
  Component.onCompleted: switchViewportSession()

  Shortcut { sequence: "Left"; context: Qt.WindowShortcut; enabled: overlay.modalActive; onActivated: mapCanvas.panBy(32, 0) }
  Shortcut { sequence: "Right"; context: Qt.WindowShortcut; enabled: overlay.modalActive; onActivated: mapCanvas.panBy(-32, 0) }
  Shortcut { sequence: "Up"; context: Qt.WindowShortcut; enabled: overlay.modalActive; onActivated: mapCanvas.panBy(0, 32) }
  Shortcut { sequence: "Down"; context: Qt.WindowShortcut; enabled: overlay.modalActive; onActivated: mapCanvas.panBy(0, -32) }
  Shortcut { sequence: "Shift+Left"; context: Qt.WindowShortcut; enabled: overlay.modalActive; onActivated: mapCanvas.panBy(96, 0) }
  Shortcut { sequence: "Shift+Right"; context: Qt.WindowShortcut; enabled: overlay.modalActive; onActivated: mapCanvas.panBy(-96, 0) }
  Shortcut { sequence: "Shift+Up"; context: Qt.WindowShortcut; enabled: overlay.modalActive; onActivated: mapCanvas.panBy(0, 96) }
  Shortcut { sequence: "Shift+Down"; context: Qt.WindowShortcut; enabled: overlay.modalActive; onActivated: mapCanvas.panBy(0, -96) }

  function boundedDuration(distance, maximum) {
    return Math.max(120, Math.min(maximum, Math.round(maximum * Math.abs(distance) / 900)))
  }

  function boundedLabel(value, maximum) {
    return String(value === undefined || value === null ? "" : value)
      .replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, maximum)
  }

  function stopMotion() {
    openingSequence.stop()
    interruptTravel.stop()
  }

  function toggleMap(userInitiated) {
    if (motionState === "closed" || motionState === "closing") openMap(userInitiated !== false)
    else closeMap(userInitiated !== false)
  }

  function toggle(userInitiated) { toggleMap(userInitiated) }

  function openMap(userInitiated) {
    var user = userInitiated !== false
    if (!available) {
      if (user) unavailableActivated(unavailableReason)
      return
    }
    if (motionState === "open" || motionState === "opening") return
    if (motionState === "closed") priorFocusItem = Window.window ? Window.window.activeFocusItem : null
    openRequested(user)
    stopMotion()
    transitionUserInitiated = user
    internalMotionState = "opening"
    opening(user)
    transitionStarted("opening", user)
    mapScope.forceActiveFocus()
    restoreViewport()
    if (user && !reduceMotion) transitionSoundRequested("open")
    if (reduceMotion) { snapOpen(user); return }
    if (paper.x <= -853.5) openingSequence.start()
    else startInterruptedTravel(true)
  }

  function closeMap(userInitiated) {
    var user = userInitiated !== false
    if (motionState === "closed" || motionState === "closing") return
    closeRequested(user)
    stopMotion()
    transitionUserInitiated = user
    internalMotionState = "closing"
    closing(user)
    transitionStarted("closing", user)
    rememberViewport()
    eraseArmed = false
    eraseReset.stop()
    if (user && !reduceMotion) transitionSoundRequested("close")
    if (reduceMotion) { snapClosed(user); return }
    startInterruptedTravel(false)
  }

  function forceClosed() {
    if (motionState === "closed" && paper.x === -854) return
    stopMotion()
    rememberViewport()
    eraseArmed = false
    eraseReset.stop()
    snapClosed(false)
  }

  function forceClose() { forceClosed() }

  function startInterruptedTravel(opening) {
    interruptTargetOpen = opening
    interruptX.from = paper.x
    interruptX.to = opening ? 46 : -854
    interruptX.duration = boundedDuration(interruptX.to - interruptX.from, opening ? 420 : 340)
    interruptRotation.from = paper.rotation
    interruptRotation.to = opening ? openRotation : closedRotation
    interruptRotation.duration = interruptX.duration
    var fadeDuration = opening ? Math.min(90, interruptX.duration) : Math.min(140, interruptX.duration)
    interruptScrimDelay.duration = opening ? 0 : Math.max(0, interruptX.duration - fadeDuration)
    interruptScrim.from = scrim.opacity
    interruptScrim.to = opening ? 0.18 : 0
    interruptScrim.duration = fadeDuration
    interruptTravel.start()
  }

  function snapOpen(user) {
    stopMotion()
    paper.x = 46
    paper.rotation = openRotation
    scrim.opacity = 0.18
    internalMotionState = "open"
    mapScope.forceActiveFocus()
    mapCanvas.invalidateGraph()
    mapCanvas.clampViewport()
    opened(user === true)
    transitionFinished("open", user === true)
  }

  function snapClosed(user) {
    stopMotion()
    paper.x = -854
    paper.rotation = closedRotation
    scrim.opacity = 0
    internalMotionState = "closed"
    closed(user === true)
    transitionFinished("closed", user === true)
    focusRestoreRequested(priorFocusItem)
    priorFocusItem = null
  }

  function finishOpening() { snapOpen(transitionUserInitiated) }
  function finishInterrupted() {
    if (interruptTargetOpen) snapOpen(transitionUserInitiated)
    else snapClosed(transitionUserInitiated)
  }

  function viewportKey(value) { return "$" + boundedLabel(value, 160) }

  function rememberViewport() {
    if (activeSessionKey === "") return
    viewportMemory[viewportKey(activeSessionKey)] = ({
      panX: mapCanvas.panX,
      panY: mapCanvas.panY,
      zoom: mapCanvas.zoom,
      userAdjusted: mapCanvas.viewportUserAdjusted
    })
  }

  function restoreViewport() {
    var saved = activeSessionKey === "" ? null : viewportMemory[viewportKey(activeSessionKey)]
    if (saved) mapCanvas.setViewport(saved.panX, saved.panY, saved.zoom, saved.userAdjusted === true)
    else mapCanvas.resetView()
  }

  function switchViewportSession() {
    if (activeSessionKey !== "" && activeSessionKey !== sessionKey) rememberViewport()
    activeSessionKey = boundedLabel(sessionKey, 160)
    restoreViewport()
  }

  function focusCurrent() { mapScope.forceActiveFocus() }
  function centerCurrent() { mapCanvas.centerCurrent() }
  function resetView() { mapCanvas.resetView() }
  function centerMap() { centerCurrent() }
  function resetMapView() { resetView() }
  function cancelErase() {
    eraseArmed = false
    eraseReset.stop()
  }

  function armErase() {
    if (!resetEnabled) return
    if (eraseArmed) {
      eraseArmed = false
      eraseReset.stop()
      resetMapRequested(activeSessionKey)
      eraseMapRequested()
      return
    }
    eraseArmed = true
    eraseReset.restart()
  }

  // The scrim is deliberately a sibling above the host CRT, never inside the
  // CRT effect source. Parent-window drag handling remains above this
  // component in the future integration layer.
  Rectangle {
    id: scrim
    x: overlay.crtRect.x
    y: overlay.crtRect.y
    width: overlay.crtRect.width
    height: overlay.crtRect.height
    color: "#000000"
    opacity: 0
    visible: overlay.modalActive || opacity > 0
  }

  MouseArea {
    id: modalBlocker
    x: 0
    y: Math.max(0, overlay.dragStripHeight)
    width: parent.width
    height: Math.max(0, parent.height - y)
    z: 1
    visible: overlay.modalActive
    enabled: visible
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    onPressed: function(mouse) { mouse.accepted = true }
    onWheel: function(wheel) { wheel.accepted = true }
  }

  Item {
    id: paper
    x: -854
    y: 29
    width: 914
    height: 682
    z: 3
    rotation: overlay.closedRotation
    transformOrigin: Item.Center
    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
      brightness: -0.16
      contrast: 0.03
      saturation: -0.04
      shadowEnabled: true
      shadowBlur: 1.0
      blurMax: 64
      shadowOpacity: 0.42
      shadowColor: "#000000"
      shadowHorizontalOffset: 10
      shadowVerticalOffset: 14
      shadowScale: 1.0
      autoPaddingEnabled: true
    }

    Image {
      anchors.fill: parent
      source: overlay.paperSource
      fillMode: Image.Stretch
      mipmap: true
      smooth: true
    }

    // Keep the vertical label inset on the visible paper while retaining a
    // slightly wider invisible hit target around it.
    Item {
      id: paperTabHitTarget
      x: parent.width - 68
      y: 85
      width: 44
      height: 100
      z: 8
      activeFocusOnTab: !overlay.modalActive
      Accessible.role: Accessible.Button
      Accessible.name: overlay.modal ? "Close explorer map, Control P" :
        (overlay.available ? "Open explorer map, Control P" : overlay.boundedLabel(overlay.unavailableReason, 96))

      Text {
        id: mapTabLabel
        anchors.centerIn: parent
        width: 92
        rotation: 90
        text: overlay.available ? "MAP / CTRL+P" : "MAP --"
        color: "#423E38"
        font.family: "monospace"
        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 0.65
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
      }

      HoverHandler { id: tabHover }
      TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: overlay.toggleMap(true)
      }

      Rectangle {
        x: 52
        y: 17
        width: unavailableTip.implicitWidth + 16
        height: 30
        z: 12
        visible: !overlay.available && tabHover.hovered
        color: "#D8D1BE"
        border.width: 1
        border.color: "#5B5349"

        Text {
          id: unavailableTip
          anchors.centerIn: parent
          text: overlay.boundedLabel(overlay.unavailableReason, 96)
          color: "#423E38"
          font.family: "monospace"
          font.pixelSize: 9
          font.bold: true
          textFormat: Text.PlainText
        }
      }
      function activateFromKey(event) {
        if (!event.isAutoRepeat) overlay.toggleMap(true)
        event.accepted = true
      }
      Keys.onReturnPressed: function(event) { paperTabHitTarget.activateFromKey(event) }
      Keys.onEnterPressed: function(event) { paperTabHitTarget.activateFromKey(event) }
      Keys.onSpacePressed: function(event) { paperTabHitTarget.activateFromKey(event) }
    }

    FocusScope {
      id: mapScope
      anchors.fill: parent
      focus: overlay.modalActive

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
          if (!event.isAutoRepeat) overlay.toggleMap(true)
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          if (!event.isAutoRepeat) {
            if (overlay.eraseArmed) overlay.cancelErase()
            else overlay.closeMap(true)
          }
          event.accepted = true
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
          mapCanvas.zoomBy(1.1, mapCanvas.width / 2, mapCanvas.height / 2)
          event.accepted = true
        } else if (event.key === Qt.Key_Minus) {
          mapCanvas.zoomBy(1 / 1.1, mapCanvas.width / 2, mapCanvas.height / 2)
          event.accepted = true
        } else if (event.key === Qt.Key_0) {
          mapCanvas.resetView()
          event.accepted = true
        }
      }

      Text {
        id: title
        anchors.left: parent.left
        anchors.leftMargin: 54
        anchors.top: parent.top
        anchors.topMargin: 36
        width: 450
        text: overlay.boundedLabel(overlay.mapTitle, 64)
        elide: Text.ElideRight
        color: "#423E38"
        font.family: "monospace"
        font.pixelSize: 17
        font.bold: true
        font.letterSpacing: 1.3
        textFormat: Text.PlainText
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: 54
        anchors.top: parent.top
        anchors.topMargin: 40
        text: mapCanvas.visitedRoomCount + " ROOMS  /  " + mapCanvas.confirmedRouteCount + " ROUTES"
        color: "#5B5349"
        font.family: "monospace"
        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 0.8
        textFormat: Text.PlainText
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 54
        anchors.rightMargin: 54
        anchors.top: parent.top
        anchors.topMargin: 70
        height: 1
        color: Qt.rgba(0.357, 0.325, 0.286, 0.48)
      }

      MapCanvas {
        id: mapCanvas
        x: 82
        y: 123
        width: 750
        height: 456
        mapState: overlay.mapState
        currentNodeId: overlay.currentNodeId
        interactionEnabled: overlay.modal
        renderScale: overlay.renderScale
        onViewportChanged: function(nextPanX, nextPanY, nextZoom) {
          if (overlay.activeSessionKey !== "") overlay.viewportMemory[overlay.viewportKey(overlay.activeSessionKey)] = ({
            panX: nextPanX, panY: nextPanY, zoom: nextZoom,
            userAdjusted: mapCanvas.viewportUserAdjusted
          })
          overlay.viewportChanged(overlay.activeSessionKey, nextPanX, nextPanY, nextZoom)
        }
      }

      Text {
        id: summaryText
        anchors.left: parent.left
        anchors.leftMargin: 54
        anchors.right: parent.right
        anchors.rightMargin: 54
        anchors.top: mapCanvas.bottom
        anchors.topMargin: 12
        height: 24
        text: mapCanvas.accessibleSummary
        elide: Text.ElideRight
        color: "#5B5349"
        font.family: "monospace"
        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 0.25
        textFormat: Text.PlainText
        Accessible.role: Accessible.StaticText
        Accessible.name: text
      }

      Row {
        id: actions
        anchors.left: parent.left
        anchors.leftMargin: 54
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        spacing: 8

        PencilButton {
          id: centerButton
          label: "CENTER"
          KeyNavigation.tab: resetButton
          onTriggered: overlay.centerCurrent()
        }
        PencilButton {
          id: resetButton
          label: "RESET VIEW"
          KeyNavigation.tab: eraseButton
          onTriggered: overlay.resetView()
        }
        PencilButton {
          id: eraseButton
          label: overlay.eraseArmed ? "ERASE? AGAIN" : "ERASE MAP"
          danger: overlay.eraseArmed
          actionEnabled: overlay.resetEnabled
          KeyNavigation.tab: closeButton
          onTriggered: overlay.armErase()
        }
        PencilButton {
          id: closeButton
          label: "CLOSE"
          KeyNavigation.tab: centerButton
          onTriggered: overlay.closeMap(true)
        }
      }

      Item {
        id: helperNotes
        anchors.right: parent.right
        anchors.rightMargin: 54
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 38
        width: 310
        height: 42

        Text {
          x: 0
          y: 17
          rotation: -1.2
          text: "arrows — pan"
          color: "#5B5349"
          font.family: "serif"
          font.pixelSize: 9
          font.italic: true
          textFormat: Text.PlainText
        }
        Text {
          x: 92
          y: 2
          rotation: 0.8
          text: "+ / − — zoom"
          color: "#5B5349"
          font.family: "serif"
          font.pixelSize: 9
          font.italic: true
          textFormat: Text.PlainText
        }
        Text {
          x: 190
          y: 20
          rotation: -0.7
          text: "0 — reset"
          color: "#5B5349"
          font.family: "serif"
          font.pixelSize: 9
          font.italic: true
          textFormat: Text.PlainText
        }
        Text {
          x: 245
          y: 5
          rotation: 1.1
          text: "esc — close"
          color: "#5B5349"
          font.family: "serif"
          font.pixelSize: 9
          font.italic: true
          textFormat: Text.PlainText
        }
      }
    }
  }

  component PencilButton: Rectangle {
    id: button
    property string label: ""
    property bool danger: false
    property bool actionEnabled: true
    signal triggered()
    width: Math.max(76, buttonLabel.implicitWidth + 22)
    height: 28
    color: activeFocus ? Qt.rgba(0.357, 0.325, 0.286, 0.16) : Qt.rgba(0.847, 0.82, 0.745, 0.34)
    border.width: activeFocus ? 2 : 1
    border.color: danger ? "#6A3F35" : "#5B5349"
    opacity: actionEnabled ? 1 : 0.46
    activeFocusOnTab: actionEnabled
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: actionEnabled ? "" : "Unavailable"
    function activateFromKey(event) {
      if (!event.isAutoRepeat && button.actionEnabled) button.triggered()
      event.accepted = true
    }
    Keys.onReturnPressed: function(event) { button.activateFromKey(event) }
    Keys.onEnterPressed: function(event) { button.activateFromKey(event) }
    Keys.onSpacePressed: function(event) { button.activateFromKey(event) }

    Text {
      id: buttonLabel
      anchors.centerIn: parent
      text: button.label
      color: button.danger ? "#6A3F35" : "#423E38"
      font.family: "monospace"
      font.pixelSize: 9
      font.bold: true
      font.letterSpacing: 0.55
      textFormat: Text.PlainText
    }
    TapHandler {
      acceptedButtons: Qt.LeftButton
      enabled: button.actionEnabled
      onTapped: { button.forceActiveFocus(); button.triggered() }
    }
  }

  Timer {
    id: eraseReset
    interval: 3000
    repeat: false
    onTriggered: overlay.eraseArmed = false
  }

  SequentialAnimation {
    id: openingSequence
    ParallelAnimation {
      NumberAnimation { target: paper; property: "x"; from: -854; to: 54; duration: 340; easing.type: Easing.OutCubic }
      NumberAnimation { target: paper; property: "rotation"; from: overlay.closedRotation; to: 1.65; duration: 340; easing.type: Easing.OutCubic }
      NumberAnimation { target: scrim; property: "opacity"; from: 0; to: 0.18; duration: 90; easing.type: Easing.OutQuad }
    }
    ParallelAnimation {
      NumberAnimation { target: paper; property: "x"; from: 54; to: 46; duration: 80; easing.type: Easing.OutQuad }
      NumberAnimation { target: paper; property: "rotation"; from: 1.65; to: overlay.openRotation; duration: 80; easing.type: Easing.OutQuad }
    }
    ScriptAction { script: overlay.finishOpening() }
  }

  ParallelAnimation {
    id: interruptTravel
    NumberAnimation { id: interruptX; target: paper; property: "x"; easing.type: overlay.interruptTargetOpen ? Easing.OutCubic : Easing.InOutCubic }
    NumberAnimation { id: interruptRotation; target: paper; property: "rotation"; easing.type: Easing.InOutCubic }
    SequentialAnimation {
      PauseAnimation { id: interruptScrimDelay }
      NumberAnimation { id: interruptScrim; target: scrim; property: "opacity"; easing.type: Easing.InOutQuad }
    }
    onFinished: overlay.finishInterrupted()
  }
}
