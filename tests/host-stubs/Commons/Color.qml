pragma Singleton
import QtQuick

// Isolated harness stand-in for the Omarchy shell's qs.Commons Color singleton.
// Panel only listens for these two change signals.
QtObject {
  property color foreground: "#cacccc"
  property var shellValues: ({})
}
