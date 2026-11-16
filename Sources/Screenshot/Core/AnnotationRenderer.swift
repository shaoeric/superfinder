import AppKit
import CoreGraphics

struct EraseStroke: Equatable {
    var points: [CGPoint]
    var brushSize: CGFloat
    var shape: EraserShape

    func draw(in context: CGContext, scale: CGFloat, selectionHeight: CGFloat) {
        guard !points.isEmpty else { return }
        context.saveGState()
        context.setBlendMode(.clear)
        context.setLineWidth(max(1, brushSize * scale))
        context.setLineCap(shape == .circle ? .round : .square)
        context.setLineJoin(shape == .circle ? .round : .miter)

        func converted(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * scale, y: (selectionHeight - p.y) * scale)
        }

        if points.count == 1 {
            let p = converted(points[0])
            let r = brushSize * scale / 2
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            context.setFillColor(NSColor.black.cgColor)
            if shape == .circle {
                context.fillEllipse(in: rect)
            } else {
                context.fill(rect)
            }
        } else {
            context.beginPath()
            context.move(to: converted(points[0]))
            for point in points.dropFirst() {
                context.addLine(to: converted(point))
            }
            context.strokePath()
        }
        context.restoreGState()
    }
}

enum EraserShape: String, CaseIterable, Equatable {
    case circle
    case square

    var displayName: String {
        switch self {
        case .circle: return "圆形"
        case .square: return "方形"
        }
    }
}

enum AnnotationRenderer {
    static func drawAll(
        _ annotations: [Annotation],
        in context: CGContext,
        scale: CGFloat,
        selectionHeight: CGFloat
    ) {
        for annotation in annotations {
            draw(
                annotation,
                in: context,
                scale: scale,
                selectionHeight: selectionHeight
            )
        }
    }

    static func draw(
        _ annotation: Annotation,
        in context: CGContext,
        scale: CGFloat,
        selectionHeight: CGFloat
    ) {
        switch annotation.kind {
        case .rectangle(let shape):
            drawRectangle(
                shape,
                color: annotation.color.nsColor,
                lineWidth: annotation.lineWidth,
                in: context,
                scale: scale,
                selectionHeight: selectionHeight
            )
        case .line(let shape):
            drawLine(
                shape,
                color: annotation.color.nsColor,
                lineWidth: annotation.lineWidth,
                in: context,
                scale: scale,
                selectionHeight: selectionHeight
            )
        case .text(let shape):
            TextLayout.draw(
                shape,
                color: annotation.color.nsColor,
                in: context,
                scale: scale,
                selectionHeight: selectionHeight
            )
        }
    }

    static func drawEraseStrokes(
        _ strokes: [EraseStroke],
        in context: CGContext,
        scale: CGFloat,
        selectionHeight: CGFloat
    ) {
        for stroke in strokes {
            stroke.draw(in: context, scale: scale, selectionHeight: selectionHeight)
        }
    }

    private static func drawRectangle(
        _ shape: RectangleShape,
        color: NSColor,
        lineWidth: CGFloat,
        in context: CGContext,
        scale: CGFloat,
        selectionHeight: CGFloat
    ) {
        let center = CGPoint(
            x: shape.center.x * scale,
            y: (selectionHeight - shape.center.y) * scale
        )
        let pixelWidth = shape.size.width * scale
        let pixelHeight = shape.size.height * scale
        guard pixelWidth > 0, pixelHeight > 0 else { return }

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -shape.angle)

        let path = CGPath(
            rect: CGRect(
                x: -pixelWidth / 2,
                y: -pixelHeight / 2,
                width: pixelWidth,
                height: pixelHeight
            ),
            transform: nil
        )
        context.addPath(path)
        if shape.filled {
            context.setFillColor(color.cgColor)
            context.fillPath()
            context.addPath(path)
        }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(max(1, lineWidth * scale))
        context.setLineJoin(.miter)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawLine(
        _ shape: LineShape,
        color: NSColor,
        lineWidth: CGFloat,
        in context: CGContext,
        scale: CGFloat,
        selectionHeight: CGFloat
    ) {
        let start = CGPoint(x: shape.start.x * scale, y: (selectionHeight - shape.start.y) * scale)
        let end = CGPoint(x: shape.end.x * scale, y: (selectionHeight - shape.end.y) * scale)
        let width = max(1, lineWidth * scale)

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.butt)
        switch shape.pattern {
        case .solid:
            context.setLineDash(phase: 0, lengths: [])
        case .dashed:
            context.setLineDash(phase: 0, lengths: [max(4, width * 3), max(3, width * 2)])
        case .dashDot:
            context.setLineDash(phase: 0, lengths: [max(5, width * 4), max(3, width * 2), max(1.5, width), max(3, width * 2)])
        }
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.1 else { return }
        let ux = dx / length
        let uy = dy / length

        if shape.endArrow != .none {
            drawArrow(at: end, direction: CGPoint(x: ux, y: uy), style: shape.endArrow, color: color, lineWidth: width, in: context)
        }
        if shape.startArrow != .none {
            drawArrow(at: start, direction: CGPoint(x: -ux, y: -uy), style: shape.startArrow, color: color, lineWidth: width, in: context)
        }
    }

    private static func drawArrow(
        at point: CGPoint,
        direction: CGPoint,
        style: ArrowStyle,
        color: NSColor,
        lineWidth: CGFloat,
        in context: CGContext
    ) {
        guard style != .none else { return }
        let length = max(8, lineWidth * 4.5)
        let angle = atan2(direction.y, direction.x)
        let spread: CGFloat = .pi / 7
        let p1 = CGPoint(
            x: point.x - cos(angle - spread) * length,
            y: point.y - sin(angle - spread) * length
        )
        let p2 = CGPoint(
            x: point.x - cos(angle + spread) * length,
            y: point.y - sin(angle + spread) * length
        )

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        if style == .thin {
            context.setLineWidth(max(1, lineWidth * 0.8))
            context.setLineCap(.round)
            context.beginPath()
            context.move(to: p1)
            context.addLine(to: point)
            context.addLine(to: p2)
            context.strokePath()
        } else {
            context.beginPath()
            context.move(to: point)
            context.addLine(to: p1)
            context.addLine(to: p2)
            context.closePath()
            context.fillPath()
        }
        context.restoreGState()
    }
}
