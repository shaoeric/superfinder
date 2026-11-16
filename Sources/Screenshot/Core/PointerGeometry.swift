import CoreGraphics

/// Geometry for converting AppKit pointer locations into the screenshot
/// overlay's screen-local, top-left-origin point space.
///
/// Drag handling deliberately takes the location carried by the event instead
/// of sampling `NSEvent.mouseLocation`. The live cursor can already be at the
/// next position while an earlier event is still being processed; using it
/// makes the selection or annotation catch up with the pointer after the user
/// has released the button, which reads as a short "trailing" drag.
enum PointerGeometry {
    /// Converts a location in a borderless overlay window's coordinate space
    /// (bottom-left origin) to the active screen's local space (top-left
    /// origin). `windowFrame` is in the same global coordinate space as
    /// `screenFrame`, so screens placed to the left or above the main display
    /// are handled without special cases.
    static func screenLocalPoint(
        eventLocationInWindow: CGPoint,
        windowFrame: CGRect,
        screenFrame: CGRect
    ) -> CGPoint {
        let global = CGPoint(
            x: windowFrame.minX + eventLocationInWindow.x,
            y: windowFrame.minY + eventLocationInWindow.y
        )
        return CGPoint(
            x: global.x - screenFrame.minX,
            y: screenFrame.maxY - global.y
        )
    }
}
