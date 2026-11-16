import AppKit
import CoreGraphics

_ = NSApplication.shared

// Synthetic 600x400 pt display captured at 2x.
let pointSize = CGSize(width: 600, height: 400)
let pixelW = 1200, pixelH = 800
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: pixelW, height: pixelH, bitsPerComponent: 8,
                    bytesPerRow: 0, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.24, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
let source = ctx.makeImage()!
let captured = try! CapturedScreen(displayID: 0,
                                   appKitFrame: CGRect(origin: .zero, size: pointSize),
                                   screenPointSize: pointSize,
                                   image: source, workingScale: 2)

let selection = CaptureSelection(rect: CGRect(x: 300, y: 180, width: 200, height: 140))
let document = ScreenshotDocument(selection: selection, workingScale: 2, baseImage: captured.image)

// Exactly what the controller does with screen-local mouse points.
let centerScreen = CGPoint(x: 360, y: 230)
let centerLocal = AnnotationSpace.local(fromScreen: centerScreen, selection: selection.rect)
document.add(Annotation(kind: .rectangle(RectangleShape(center: centerLocal,
                                                        size: CGSize(width: 80, height: 50),
                                                        angle: 0, mosaic: 0)),
                        color: .annotationRed, lineWidth: 6))
let lineStart = AnnotationSpace.local(fromScreen: CGPoint(x: 330, y: 300), selection: selection.rect)
let lineEnd = AnnotationSpace.local(fromScreen: CGPoint(x: 450, y: 295), selection: selection.rect)
document.add(Annotation(kind: .line(LineShape(start: lineStart, end: lineEnd, pattern: .solid,
                                              startArrow: .none, endArrow: .thick)),
                        color: .annotationYellow, lineWidth: 4))

let view = CaptureOverlayView(frame: CGRect(origin: .zero, size: pointSize))
let window = NSWindow(contentRect: CGRect(origin: .zero, size: pointSize),
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = view
view.setActive(true)
view.setCapturedScreen(captured)
view.setSession(document: document, selection: selection, tool: .pointer)
view.layoutSubtreeIfNeeded()

let scale: CGFloat = 2
let outW = Int(pointSize.width * scale), outH = Int(pointSize.height * scale)
let bmp = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bmp.scaleBy(x: scale, y: scale)
bmp.translateBy(x: 0, y: pointSize.height)
bmp.scaleBy(x: 1, y: -1)
view.layer?.render(in: bmp)
guard let rendered = bmp.makeImage() else { print("FAIL: no render"); exit(1) }

// Scan for the annotation red outline.
var minX = outW, maxX = 0, minY = outH, maxY = 0, redCount = 0
let data = bmp.data!.assumingMemoryBound(to: UInt8.self)
for y in 0..<outH {
    for x in 0..<outW {
        let o = y * bmp.bytesPerRow + x * 4
        let r = data[o], g = data[o+1], b = data[o+2]
        if r > 200 && g < 90 && b < 90 {
            redCount += 1
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
let expected = (x: Int(320*scale)...Int(400*scale), yTop: Int(205*scale)...Int(255*scale))
print("red pixels: \(redCount)")
print("red bbox: x \(minX)...\(maxX)  y \(minY)...\(maxY)")
print("expected (top-left coords): x \(expected.x.lowerBound)...\(expected.x.upperBound)  y \(expected.yTop.lowerBound)...\(expected.yTop.upperBound)")

let xOK = minX >= expected.x.lowerBound - 8 && maxX <= expected.x.upperBound + 8
let yOKTop = minY >= expected.yTop.lowerBound - 8 && maxY <= expected.yTop.upperBound + 8
let yOKBottom = minY >= outH - expected.yTop.upperBound - 8 && maxY <= outH - expected.yTop.lowerBound + 8
print("xOK=\(xOK) yTopOK=\(yOKTop) yBottomOK=\(yOKBottom)")
if redCount > 0 && xOK && (yOKTop || yOKBottom) {
    print("PASS: annotation renders at the expected selection-local position")
} else {
    print("FAIL: annotation position mismatch")
    exit(2)
}
