import CoreGraphics

/// Single source of truth for converting between screen-local points (top-left
/// origin of the captured display, points) and selection-local points (the
/// coordinate space every annotation is stored in).
///
/// Annotations are always stored relative to the selection's top-left corner so
/// that moving or resizing the selection carries them along. Rendering adds the
/// selection origin back exactly once.
enum AnnotationSpace {
    static func local(fromScreen point: CGPoint, selection: CGRect) -> CGPoint {
        CGPoint(x: point.x - selection.minX, y: point.y - selection.minY)
    }

    static func screen(fromLocal point: CGPoint, selection: CGRect) -> CGPoint {
        CGPoint(x: point.x + selection.minX, y: point.y + selection.minY)
    }

    static func screen(fromLocal rect: CGRect, selection: CGRect) -> CGRect {
        rect.offsetBy(dx: selection.minX, dy: selection.minY)
    }

    static func local(fromScreen rect: CGRect, selection: CGRect) -> CGRect {
        rect.offsetBy(dx: -selection.minX, dy: -selection.minY)
    }

    /// Annotation geometry must never leak screen coordinates into the model.
    static func isConsistent(annotation: Annotation, selection: CGRect) -> Bool {
        let margin: CGFloat = 2
        switch annotation.kind {
        case .rectangle(let shape):
            let bounds = shape.axisAlignedBounds
            return bounds.maxX <= selection.width + margin && bounds.maxY <= selection.height + margin
        case .line(let shape):
            return shape.start.x <= selection.width + margin
                && shape.start.y <= selection.height + margin
                && shape.end.x <= selection.width + margin
                && shape.end.y <= selection.height + margin
        case .text(let shape):
            let bounds = shape.bounds
            return bounds.maxX <= selection.width + margin && bounds.maxY <= selection.height + margin
        }
    }
}
