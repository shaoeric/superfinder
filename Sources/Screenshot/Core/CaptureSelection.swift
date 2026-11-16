import CoreGraphics
import Foundation

enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
}

/// Selection rectangle in the active screen's local, top-left-origin points.
struct CaptureSelection: Equatable {
    static let minimumSize: CGFloat = 4
    static let cornerHitRadius: CGFloat = 22
    static let edgeHitBand: CGFloat = 12

    var rect: CGRect

    init(rect: CGRect) {
        self.rect = rect.standardized
    }

    init(anchor: CGPoint, current: CGPoint) {
        self.rect = CGRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(current.x - anchor.x),
            height: abs(current.y - anchor.y)
        )
    }

    var isUsable: Bool {
        rect.width >= Self.minimumSize && rect.height >= Self.minimumSize
    }

    func contains(_ point: CGPoint) -> Bool {
        rect.contains(point)
    }

    /// Generous hit testing for the eight resize handles. Corners get a larger
    /// circular target; the entire length of each edge is a resize target, not
    /// just its midpoint. This makes the handles practical on high-resolution
    /// screens without changing the visual selection rectangle.
    func handle(at point: CGPoint) -> SelectionHandle? {
        let corners: [(SelectionHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY))
        ]
        var best: (SelectionHandle, CGFloat)?
        for (handle, center) in corners {
            let distance = hypot(center.x - point.x, center.y - point.y)
            if distance <= Self.cornerHitRadius, distance < (best?.1 ?? .greatestFiniteMagnitude) {
                best = (handle, distance)
            }
        }
        if let best { return best.0 }

        let extendedX = rect.minX - Self.edgeHitBand ... rect.maxX + Self.edgeHitBand
        let extendedY = rect.minY - Self.edgeHitBand ... rect.maxY + Self.edgeHitBand

        if extendedX.contains(point.x) {
            if abs(point.y - rect.minY) <= Self.edgeHitBand { return .top }
            if abs(point.y - rect.maxY) <= Self.edgeHitBand { return .bottom }
        }
        if extendedY.contains(point.y) {
            if abs(point.x - rect.minX) <= Self.edgeHitBand { return .left }
            if abs(point.x - rect.maxX) <= Self.edgeHitBand { return .right }
        }
        return nil
    }

    var handleCenters: [(SelectionHandle, CGPoint)] {
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let midX = rect.midX
        let midY = rect.midY
        return [
            (.topLeft, CGPoint(x: minX, y: minY)),
            (.top, CGPoint(x: midX, y: minY)),
            (.topRight, CGPoint(x: maxX, y: minY)),
            (.right, CGPoint(x: maxX, y: midY)),
            (.bottomRight, CGPoint(x: maxX, y: maxY)),
            (.bottom, CGPoint(x: midX, y: maxY)),
            (.bottomLeft, CGPoint(x: minX, y: maxY)),
            (.left, CGPoint(x: minX, y: midY))
        ]
    }

    mutating func move(by delta: CGPoint, within bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        var moved = rect.offsetBy(dx: delta.x, dy: delta.y)
        if moved.minX < bounds.minX { moved.origin.x = bounds.minX }
        if moved.minY < bounds.minY { moved.origin.y = bounds.minY }
        if moved.maxX > bounds.maxX { moved.origin.x = bounds.maxX - moved.width }
        if moved.maxY > bounds.maxY { moved.origin.y = bounds.maxY - moved.height }
        rect = moved
    }

    mutating func resize(handle: SelectionHandle, by delta: CGPoint, within bounds: CGRect) {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        if handle.movesLeft { minX += delta.x }
        if handle.movesRight { maxX += delta.x }
        if handle.movesTop { minY += delta.y }
        if handle.movesBottom { maxY += delta.y }

        minX = max(bounds.minX, min(minX, maxX - Self.minimumSize))
        minY = max(bounds.minY, min(minY, maxY - Self.minimumSize))
        maxX = min(bounds.maxX, max(maxX, minX + Self.minimumSize))
        maxY = min(bounds.maxY, max(maxY, minY + Self.minimumSize))

        rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    mutating func clamp(to bounds: CGRect) {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        rect = CGRect(x: x, y: y, width: width, height: height)
    }
}
