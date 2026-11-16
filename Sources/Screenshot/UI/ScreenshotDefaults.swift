import AppKit

struct ScreenshotDefaults {
    var rectangleColor: RGBAColor = .annotationRed
    var rectangleWidth: CGFloat = 3
    var rectangleFilled: Bool = false

    var lineColor: RGBAColor = .annotationRed
    var lineWidth: CGFloat = 3
    var linePattern: LinePattern = .solid
    var lineStartArrow: ArrowStyle = .none
    var lineEndArrow: ArrowStyle = .none

    var textColor: RGBAColor = .annotationRed
    var textFontName: String = TextFontOption(displayName: "系统", postScriptName: nil).postScriptName ?? ""
    var textFontSize: CGFloat = 24

    var eraserSize: CGFloat = 24
    var eraserShape: EraserShape = .circle
}
