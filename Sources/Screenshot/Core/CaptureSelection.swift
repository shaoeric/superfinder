import CoreGraphics
import Foundation

enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool {
        self == .topLeft || self == .left || self == .bottomLeft
    }

    var movesRight: Bool {
        self == .topRight || self == .right || self == .bottomRight
    }

    var movesTop: Bool {
        self == .topLeft || self == .top || self == .topRight
    }

    var movesBottom: Bool {
        self == .bottomLeft || self == .bottom || self == .bottomRight
    }
}

/// Selection rectangle in the active screen's local, top-left-origin points.
struct CaptureSelection: Equatable {
    static let minimumSize: CGFloat = 4
    static let handleHitRadius: CGFloat = 9

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

    func handle(at point: CGPoint) -> SelectionHandle? {
        for (handle, center) in handleCenters {
            if hypot(center.x - point.x, center.y - point.y) <= Self.handleHitRadius {
                return handle
            }
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
