import QtQuick
import QtQuick.Shapes
import qs.Commons

// Vector geometry, so the mark takes the theme foreground at any bar size.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  // Measured ink bounds, not the viewBox: that is what matches neighbour weight.
  readonly property real boxWidth: 24.0
  readonly property real boxTop: 2.85
  readonly property real boxHeight: 18.3

  // Clyde is solid where its bar neighbours are sparse; 0.85 matches their ink (NOTES.md).
  readonly property real opticalScale: 0.85

  implicitWidth: iconSize * opticalScale * (boxWidth / boxHeight)
  implicitHeight: iconSize * opticalScale
  width: implicitWidth
  height: implicitHeight

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    transform: [
      Scale {
        xScale: root.width / root.boxWidth
        yScale: root.height / root.boxHeight
      },
      Translate {
        y: -root.boxTop * (root.height / root.boxHeight)
      }
    ]

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      // Odd-even makes the eyes holes whichever way they are wound.
      fillRule: ShapePath.OddEvenFill

      // The 17 corner arcs are drawn as lines; Qt mis-parses the compact form (NOTES.md).
      PathSvg {
        path: "M 20.317 4.3698 l -4.8851 -1.5152 l -0.0785 0.0371 c -0.211 0.3753 -0.4447 0.8648 -0.6083 1.2495 c -1.8447 -0.2762 -3.68 -0.2762 -5.4868 0 c -0.1636 -0.3933 -0.4058 -0.8742 -0.6177 -1.2495 l -0.0785 -0.037 l -4.8852 1.515 l -0.0321 0.0277 C 0.5334 9.0458 -0.319 13.5799 0.0992 18.0578 l 0.0312 0.0561 c 2.0528 1.5076 4.0413 2.4228 5.9929 3.0294 l 0.0842 -0.0276 c 0.4616 -0.6304 0.8731 -1.2952 1.226 -1.9942 l -0.0416 -0.1057 c -0.6528 -0.2476 -1.2743 -0.5495 -1.8722 -0.8923 l -0.0076 -0.1277 c 0.1258 -0.0943 0.2517 -0.1923 0.3718 -0.2914 l 0.0776 -0.0105 c 3.9278 1.7933 8.18 1.7933 12.0614 0 l 0.0785 0.0095 c 0.1202 0.099 0.246 0.1981 0.3728 0.2924 l -0.0066 0.1276 l -1.873 0.8914 l -0.0407 0.1067 c 0.3604 0.698 0.7719 1.3628 1.225 1.9932 l 0.0842 0.0286 c 1.961 -0.6067 3.9495 -1.5219 6.0023 -3.0294 l 0.0313 -0.0552 c 0.5004 -5.177 -0.8382 -9.6739 -3.5485 -13.6604 l -0.0312 -0.0286 z M 8.02 15.3312 c -1.1825 0 -2.1569 -1.0857 -2.1569 -2.419 c 0 -1.3332 0.9555 -2.4189 2.157 -2.4189 c 1.2108 0 2.1757 1.0952 2.1568 2.419 c 0 1.3332 -0.9555 2.4189 -2.1569 2.4189 z m 7.9748 0 c -1.1825 0 -2.1569 -1.0857 -2.1569 -2.419 c 0 -1.3332 0.9554 -2.4189 2.1569 -2.4189 c 1.2108 0 2.1757 1.0952 2.1568 2.419 c 0 1.3332 -0.946 2.4189 -2.1568 2.4189 z"
      }
    }
  }
}
