import AppKit
import CoreGraphics

struct RGBAColor: Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var cgColor: CGColor {
        nsColor.cgColor
    }

    static let annotationRed = RGBAColor(0.96, 0.20, 0.18)
    static let annotationYellow = RGBAColor(1.0, 0.78, 0.12)
    static let annotationWhite = RGBAColor(1, 1, 1)
    static let annotationBlue = RGBAColor(0.16, 0.56, 1.0)
    static let annotationBlack = RGBAColor(0.05, 0.05, 0.05)
}

enum LinePattern: String, CaseIterable {
    case solid
    case dashed
    case dashDot

    var displayName: String {
        switch self {
        case .solid: return "实线"
        case .dashed: return "虚线"
        case .dashDot: return "点划线"
        }
    }
}

enum ArrowStyle: String, CaseIterable {
    case none
    case thin
    case thick

    var displayName: String {
        switch self {
        case .none: return "无"
        case .thin: return "细箭头"
        case .thick: return "粗箭头"
        }
    }
}

struct RectangleShape: Equatable {
    var center: CGPoint
    var size: CGSize
    var angle: CGFloat
    /// When true the rectangle is filled with the same color as its outline.
    var filled: Bool

    var halfWidth: CGFloat { size.width / 2 }
    var halfHeight: CGFloat { size.height / 2 }

    func localToScreen(_ point: CGPoint) -> CGPoint {
        let c = cos(angle)
        let s = sin(angle)
        return CGPoint(
            x: center.x + point.x * c - point.y * s,
            y: center.y + point.x * s + point.y * c
        )
    }

    func screenToLocal(_ point: CGPoint) -> CGPoint {
        let c = cos(angle)
        let s = sin(angle)
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(x: dx * c + dy * s, y: -dx * s + dy * c)
    }

    var corners: [CGPoint] {
        let hw = halfWidth
        let hh = halfHeight
        return [
            localToScreen(CGPoint(x: -hw, y: -hh)),
            localToScreen(CGPoint(x: hw, y: -hh)),
            localToScreen(CGPoint(x: hw, y: hh)),
            localToScreen(CGPoint(x: -hw, y: hh))
        ]
    }

    var axisAlignedBounds: CGRect {
        let points = corners
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
    }

    func contains(_ point: CGPoint) -> Bool {
        let local = screenToLocal(point)
        return abs(local.x) <= halfWidth && abs(local.y) <= halfHeight
    }

    mutating func move(by delta: CGPoint) {
        center.x += delta.x
        center.y += delta.y
    }
}

struct LineShape: Equatable {
    var start: CGPoint
    var end: CGPoint
    var pattern: LinePattern
    var startArrow: ArrowStyle
    var endArrow: ArrowStyle

    var bounds: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).insetBy(dx: -8, dy: -8)
    }

    func distance(to point: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.001 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let px = start.x + t * dx
        let py = start.y + t * dy
        return hypot(point.x - px, point.y - py)
    }

    mutating func move(by delta: CGPoint) {
        start.x += delta.x
        start.y += delta.y
        end.x += delta.x
        end.y += delta.y
    }
}

struct TextShape: Equatable {
    var origin: CGPoint
    var text: String
    var fontName: String
    var fontSize: CGFloat

    var bounds: CGRect {
        let size = TextLayout.size(text: text, fontName: fontName, fontSize: fontSize)
        return CGRect(origin: origin, size: size)
    }

    mutating func move(by delta: CGPoint) {
        origin.x += delta.x
        origin.y += delta.y
    }
}

enum AnnotationKind: Equatable {
    case rectangle(RectangleShape)
    case line(LineShape)
    case text(TextShape)

    var displayName: String {
        switch self {
        case .rectangle: return "矩形"
        case .line: return "线段"
        case .text: return "文本"
        }
    }
}

struct Annotation: Identifiable, Equatable {
    let id: UUID
    var kind: AnnotationKind
    var color: RGBAColor
    var lineWidth: CGFloat

    init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        color: RGBAColor = .annotationRed,
        lineWidth: CGFloat = 3
    ) {
        self.id = id
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }

    var bounds: CGRect {
        switch kind {
        case .rectangle(let rect):
            return rect.axisAlignedBounds.insetBy(dx: -12, dy: -12)
        case .line(let line):
            return line.bounds
        case .text(let text):
            return text.bounds.insetBy(dx: -4, dy: -4)
        }
    }

    var center: CGPoint {
        switch kind {
        case .rectangle(let rect):
            return rect.center
        case .line(let line):
            return CGPoint(x: (line.start.x + line.end.x) / 2, y: (line.start.y + line.end.y) / 2)
        case .text(let text):
            let b = text.bounds
            return CGPoint(x: b.midX, y: b.midY)
        }
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat = 6) -> Bool {
        switch kind {
        case .rectangle(let shape):
            if shape.filled && shape.contains(point) { return true }
            let corners = shape.corners
            for index in corners.indices {
                let a = corners[index]
                let b = corners[(index + 1) % corners.count]
                if Self.distance(from: point, toSegmentFrom: a, to: b) <= max(tolerance, lineWidth / 2 + 3) {
                    return true
                }
            }
            return shape.contains(point)
        case .line(let shape):
            return shape.distance(to: point) <= max(tolerance, lineWidth / 2 + 4)
        case .text(let shape):
            return shape.bounds.insetBy(dx: -2, dy: -2).contains(point)
        }
    }

    /// Approximate hit test for the eraser. For text this uses the text bounds
    /// (line rectangles would be tighter, but the final erase is pixel exact).
    func intersectsBrush(center: CGPoint, radius: CGFloat) -> Bool {
        switch kind {
        case .rectangle(let shape):
            if shape.filled, shape.contains(center) { return true }
            let corners = shape.corners
            for index in corners.indices {
                let a = corners[index]
                let b = corners[(index + 1) % corners.count]
                if Self.distance(from: center, toSegmentFrom: a, to: b) <= radius + lineWidth / 2 {
                    return true
                }
            }
            return false
        case .line(let shape):
            return shape.distance(to: center) <= radius + lineWidth / 2
        case .text(let shape):
            return shape.bounds.insetBy(dx: -radius, dy: -radius).contains(center)
        }
    }

    func handlesForEditing() -> [CGPoint] {
        switch kind {
        case .rectangle(let shape):
            return shape.corners
        case .line(let shape):
            return [shape.start, shape.end]
        case .text:
            return []
        }
    }

    func selectionOutlinePoints() -> [CGPoint] {
        switch kind {
        case .rectangle(let shape):
            return shape.corners
        case .line(let shape):
            let dx = shape.end.x - shape.start.x
            let dy = shape.end.y - shape.start.y
            let length = max(0.001, hypot(dx, dy))
            let nx = -dy / length * 10
            let ny = dx / length * 10
            return [
                CGPoint(x: shape.start.x + nx, y: shape.start.y + ny),
                CGPoint(x: shape.end.x + nx, y: shape.end.y + ny),
                CGPoint(x: shape.end.x - nx, y: shape.end.y - ny),
                CGPoint(x: shape.start.x - nx, y: shape.start.y - ny)
            ]
        case .text(let shape):
            let b = shape.bounds.insetBy(dx: -6, dy: -6)
            return [
                CGPoint(x: b.minX, y: b.minY),
                CGPoint(x: b.maxX, y: b.minY),
                CGPoint(x: b.maxX, y: b.maxY),
                CGPoint(x: b.minX, y: b.maxY)
            ]
        }
    }

    /// Delete affordance, pushed well outside the oriented box so it does not
    /// collide with the corner resize handle or the line endpoints.
    func deleteHandlePoint() -> CGPoint {
        let outline = selectionOutlinePoints()
        let topRight = outline[1]
        return CGPoint(x: topRight.x + 22, y: topRight.y - 22)
    }

    /// Rotation affordance for rectangles. It sits outside the top-left corner
    /// in the rectangle's own rotated space, so it never collides with the
    /// delete button at the top-right or the corner resize handles.
    func rotationHandlePoint() -> CGPoint? {
        guard case .rectangle(let shape) = kind else { return nil }
        return shape.localToScreen(CGPoint(
            x: -shape.halfWidth - 22,
            y: -shape.halfHeight - 22
        ))
    }

    mutating func move(by delta: CGPoint) {
        switch kind {
        case .rectangle(var shape):
            shape.move(by: delta)
            kind = .rectangle(shape)
        case .line(var shape):
            shape.move(by: delta)
            kind = .line(shape)
        case .text(var shape):
            shape.move(by: delta)
            kind = .text(shape)
        }
    }

    mutating func resize(handleIndex: Int, by delta: CGPoint) {
        switch kind {
        case .rectangle(var shape):
            let c = cos(shape.angle)
            let s = sin(shape.angle)
            let localDelta = CGPoint(
                x: delta.x * c + delta.y * s,
                y: -delta.x * s + delta.y * c
            )
            let signs: [(CGFloat, CGFloat)] = [
                (-1, -1), (1, -1), (1, 1), (-1, 1)
            ]
            guard signs.indices.contains(handleIndex) else { return }
            let (sx, sy) = signs[handleIndex]
            var newWidth = max(8, shape.size.width + localDelta.x * sx)
            var newHeight = max(8, shape.size.height + localDelta.y * sy)
            let localCenterShift = CGPoint(
                x: (newWidth - shape.size.width) * sx / 2,
                y: (newHeight - shape.size.height) * sy / 2
            )
            newWidth = max(8, newWidth)
            newHeight = max(8, newHeight)
            let worldShift = CGPoint(
                x: localCenterShift.x * c - localCenterShift.y * s,
                y: localCenterShift.x * s + localCenterShift.y * c
            )
            shape.center.x += worldShift.x
            shape.center.y += worldShift.y
            shape.size = CGSize(width: newWidth, height: newHeight)
            kind = .rectangle(shape)
        case .line(var shape):
            if handleIndex == 0 { shape.start = CGPoint(x: shape.start.x + delta.x, y: shape.start.y + delta.y) }
            if handleIndex == 1 { shape.end = CGPoint(x: shape.end.x + delta.x, y: shape.end.y + delta.y) }
            kind = .line(shape)
        case .text:
            break
        }
    }

    mutating func setRotation(_ angle: CGFloat) {
        guard case .rectangle(var shape) = kind else { return }
        shape.angle = angle
        kind = .rectangle(shape)
    }

    static func distance(from point: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0001 else { return hypot(point.x - a.x, point.y - a.y) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}
