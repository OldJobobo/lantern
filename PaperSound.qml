pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia

Item {
  id: audio
  property bool muted: false
  property bool reduceMotion: false
  property real volume: 0.18
  // Tests can observe requests without initializing an audio device.
  property bool playbackEnabled: true
  signal playbackRequested(string kind)
  readonly property var player: effects.item

  function stop() {
    if (player) player.stop()
  }

  function request(kind) {
    stop()
    if (muted || reduceMotion || volume <= 0 || (kind !== "open" && kind !== "close")) return
    playbackRequested(kind)
    if (player) player.play(kind)
  }

  onMutedChanged: { if (muted) stop() }
  onReduceMotionChanged: { if (reduceMotion) stop() }

  Loader {
    id: effects
    active: audio.playbackEnabled && !audio.muted && !audio.reduceMotion
    sourceComponent: Component {
      Item {
        function stop() { opening.stop(); closing.stop() }
        function play(kind) {
          if (kind === "open" && opening.status === SoundEffect.Ready) opening.play()
          else if (kind === "close" && closing.status === SoundEffect.Ready) closing.play()
        }
        SoundEffect {
          id: opening
          source: Qt.resolvedUrl("assets/paper-map-open.wav")
          volume: Math.max(0, Math.min(1, audio.volume))
          loops: 1
        }
        SoundEffect {
          id: closing
          source: Qt.resolvedUrl("assets/paper-map-close.wav")
          volume: Math.max(0, Math.min(1, audio.volume))
          loops: 1
        }
      }
    }
  }
}
