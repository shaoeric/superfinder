import AppKit
import CoreGraphics

struct TextFontOption: Equatable {
    let displayName: String
    let postScriptName: String?
}

enum TextLayout {
    static let fontOptions: [TextFontOption] = [
        TextFontOption(displayName: "系统", postScriptName: nil),
        TextFontOption(displayName: "苹方", postScriptName: "PingFangSC-Regular"),
        TextFontOption(displayName: "宋体", postScriptName: "SongtiSC-Regular"),
        TextFontOption(displayName: "黑体", postScriptName: "STHeitiSC-Light"),
        TextFontOption(displayName: "楷体", postScriptName: "STKaitiSC-Regular"),
        TextFontOption(displayName: "Helvetica Neue", postScriptName: "HelveticaNeue"),
        TextFontOption(displayName: "Menlo", postScriptName: "Menlo-Regular")
    ]

    static func font(name: String, size: CGFloat) -> NSFont {
        if let font = NSFont(name: name, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size)
    }

    static func attributedString(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        color: NSColor
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        paragraph.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(name: fontName, size: fontSize),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    static func size(text: String, fontName: String, fontSize: CGFloat) -> CGSize {
        guard !text.isEmpty else {
            return CGSize(width: 8, height: max(12, fontSize))
        }
        let attributed = attributedString(
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            color: .white
        )
        let bounds = attributed.boundingRect(
            with: CGSize(width: 8192, height: 8192),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(
            width: max(4, ceil(bounds.width) + 2),
            height: max(fontSize, ceil(bounds.height) + 2)
        )
    }

    static func draw(
        _ shape: TextShape,
        color: NSColor,
        in context: CGContext,
        scale: CGFloat,
        selectionHeight: CGFloat
    ) {
        guard !shape.text.isEmpty else { return }
        let attributed = attributedString(
            text: shape.text,
            fontName: shape.fontName,
            fontSize: shape.fontSize,
            color: color
        )
        let size = self.size(text: shape.text, fontName: shape.fontName, fontSize: shape.fontSize)
        let rect = CGRect(
            x: shape.origin.x * scale,
            y: (selectionHeight - shape.origin.y - size.height) * scale,
            width: size.width * scale,
            height: size.height * scale
        )

        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphics
        attributed.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}
