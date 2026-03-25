pragma Singleton
import QtQuick

QtObject {
    // Background layers
    readonly property color bg0: "#0F0808"
    readonly property color bg1: "#1C1210"
    readonly property color bg2: "#2D1F1A"
    readonly property color bg3: "#3E2C25"

    // Accents and borders
    readonly property color border: "#C23A22"
    readonly property color accent1: "#D4391E"
    readonly property color accent2: "#E07A30"

    // Text
    readonly property color text: "#E8CFC0"
    readonly property color textDim: "#A08070"

    // Font
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 12
}
