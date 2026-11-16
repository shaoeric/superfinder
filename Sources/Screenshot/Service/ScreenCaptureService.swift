import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case unsupportedSystem
    case displayNotFound
    case captureFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "截屏功能需要 macOS 14 或更高版本。"
        case .displayNotFound:
            return "找不到当前显示器的截屏源。"
        case .captureFailed(let message):
            return "截屏失败：\(message)"
        case .timedOut:
            return "截屏超时，请重试。"
        }
    }
}

final class ScreenCaptureService {
    private var generation = 0

    /// Captures exactly one active display at a capped working resolution.
    func capture(
        screen: NSScreen,
        completion: @escaping (Result<CapturedScreen, Error>) -> Void
    ) {
        generation += 1
        let token = generation

        guard #available(macOS 14.0, *) else {
            completion(.failure(ScreenCaptureError.unsupportedSystem))
            return
        }
        guard let displayID = Self.displayID(for: screen) else {
            completion(.failure(ScreenCaptureError.displayNotFound))
            return
        }

        let pointSize = screen.frame.size
        let screenFrame = screen.frame
        let scale = MemoryBudget.workingScale(forPointSize: pointSize)
        let pixels = MemoryBudget.pixelSize(forPointSize: pointSize, scale: scale)
        var finished = false
        let finish: (Result<CapturedScreen, Error>) -> Void = { [weak self] result in
            guard let self, !finished, token == self.generation else { return }
            finished = true
            DispatchQueue.main.async {
                completion(result)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            finish(.failure(ScreenCaptureError.timedOut))
        }

        Task {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    finish(.failure(ScreenCaptureError.displayNotFound))
                    return
                }

                let ownApps = content.applications.filter {
                    $0.bundleIdentifier == AppConfig.hostBundleID
                }
                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: ownApps,
                    exceptingWindows: []
                )

                let configuration = SCStreamConfiguration()
                configuration.width = pixels.width
                configuration.height = pixels.height
                configuration.showsCursor = false
                configuration.capturesAudio = false
                configuration.queueDepth = 1
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.colorSpaceName = CGColorSpace.sRGB
                configuration.captureResolution = .best
                configuration.scalesToFit = true

                SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                ) { image, error in
                    if let error {
                        finish(.failure(ScreenCaptureError.captureFailed(error.localizedDescription)))
                        return
                    }
                    guard let image else {
                        finish(.failure(ScreenCaptureError.captureFailed("没有返回图像")))
                        return
                    }
                    DispatchQueue.main.async {
                        do {
                            let captured = try CapturedScreen(
                                displayID: displayID,
                                appKitFrame: screenFrame,
                                screenPointSize: pointSize,
                                image: image,
                                workingScale: scale
                            )
                            finish(.success(captured))
                        } catch {
                            finish(.failure(error))
                        }
                    }
                }
            } catch {
                finish(.failure(ScreenCaptureError.captureFailed(error.localizedDescription)))
            }
        }
    }

    func cancel() {
        generation += 1
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
