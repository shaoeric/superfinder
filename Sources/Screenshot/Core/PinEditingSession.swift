import CoreGraphics

/// Keeps everything needed to reopen a pinned image in the full screenshot
/// editor: the original full-display capture, the live annotation document
/// (selection, vectors, frozen raster and undo history), and the screen
/// geometry. `PinnedImageWindow` owns the session for as long as the pin
/// exists; the editor borrows it while the toolbar is visible.
final class PinEditingSession {
    let capturedScreen: CapturedScreen
    let document: ScreenshotDocument

    init(capturedScreen: CapturedScreen, document: ScreenshotDocument) {
        self.capturedScreen = capturedScreen
        self.document = document
    }

    var screenFrame: CGRect { capturedScreen.appKitFrame }
    var selection: CaptureSelection { document.selection }
}
