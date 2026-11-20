// Draws the Local Monitor app icon and writes the PNGs of an .iconset into an existing directory.
// Usage: make-app-icon <output.iconset directory>
// Compiled by scripts/build-app.sh with `xcrun swiftc -parse-as-library` into .build/; no
// dependencies beyond AppKit. Every image is rendered into an NSBitmapImageRep of exact pixel
// size, so the output does not depend on the screen scale factor (CI runners are headless).
import AppKit

@main
enum MakeAppIcon {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else { fail("usage: make-app-icon <output.iconset directory>") }
        let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            fail("not an existing directory: \(directory.path)")
        }
        // iconutil's required names: icon_<points>x<points>[@2x].png.
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let rep = IconRenderer.render(pixels: pixels)
                // Metadata only: a 2x image reports its point size so it carries 144 dpi.
                rep.size = NSSize(width: points, height: points)
                guard let data = rep.representation(using: .png, properties: [:]) else {
                    fail("PNG encoding failed at \(pixels) px")
                }
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                do {
                    try data.write(to: directory.appendingPathComponent(name), options: .atomic)
                } catch {
                    fail("cannot write \(name): \(error)")
                }
            }
        }
        print("App icon: wrote 10 PNG files (\(IconRenderer.glyphSource)) to \(directory.lastPathComponent)")
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-app-icon: \(message)\n".utf8))
    exit(1)
}

@MainActor
enum IconRenderer {
    /// Symbols tried in order; the drawn gauge below is the final fallback.
    static let symbolNames = ["gauge.medium", "gauge", "speedometer", "chart.bar.fill"]
    static var glyphSource = "not rendered"

    static func render(pixels: Int) -> NSBitmapImageRep {
        let size = CGFloat(pixels)
        let canvas = NSRect(x: 0, y: 0, width: size, height: size)
        let rep = bitmap(pixels: pixels)
        draw(into: rep) {
            NSColor.clear.set()
            canvas.fill(using: .copy)
            // macOS icon grid: 824/1024 body with ~10 % transparent margin on each side.
            let inset = (size * 100 / 1024).rounded()
            let body = canvas.insetBy(dx: inset, dy: inset)
            let shape = continuousRoundedSquare(body, cornerRadius: body.width * 0.225)
            let top = NSColor(srgbRed: 0.07, green: 0.17, blue: 0.40, alpha: 1)    // dark blue
            let bottom = NSColor(srgbRed: 0.05, green: 0.52, blue: 0.56, alpha: 1) // teal
            guard let gradient = NSGradient(starting: bottom, ending: top) else { fail("gradient") }
            gradient.draw(in: shape, angle: 90) // 90 degrees: starting colour at the bottom
            // Hairline inner edge keeps the shape readable on dark backgrounds.
            NSColor(white: 1, alpha: 0.12).setStroke()
            shape.lineWidth = max(1, size / 512)
            shape.stroke()
            let glyph = whiteGlyph(pixels: pixels, in: body)
            _ = glyph.draw(in: canvas, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        }
        return rep
    }

    static func bitmap(pixels: Int) -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { fail("cannot allocate a \(pixels) px bitmap") }
        // Drawing coordinates are pixels; callers may change size afterwards (metadata only).
        rep.size = NSSize(width: pixels, height: pixels)
        return rep
    }

    static func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { fail("no bitmap graphics context") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.shouldAntialias = true
        body()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Rounded square whose corners are superellipse quarters: curvature eases in from the
    /// straight edges like Apple's continuous corners. The corner extent is 1.528 r and the
    /// exponent is chosen so the diagonal depth equals that of a circular corner of radius r.
    static func continuousRoundedSquare(_ rect: NSRect, cornerRadius r: CGFloat) -> NSBezierPath {
        let extent = min(1.528 * r, rect.width / 2, rect.height / 2)
        let exponent: CGFloat = 3.26
        let steps = 64
        let path = NSBezierPath()
        // (corner, inward x, inward y, reversed): walked counter-clockwise from the bottom left.
        let corners: [(NSPoint, CGFloat, CGFloat, Bool)] = [
            (NSPoint(x: rect.minX, y: rect.minY), 1, 1, false),
            (NSPoint(x: rect.maxX, y: rect.minY), -1, 1, true),
            (NSPoint(x: rect.maxX, y: rect.maxY), -1, -1, false),
            (NSPoint(x: rect.minX, y: rect.maxY), 1, -1, true),
        ]
        var first = true
        for (corner, ex, ey, reversed) in corners {
            for step in 0...steps {
                let fraction = CGFloat(reversed ? steps - step : step) / CGFloat(steps)
                let t = fraction * .pi / 2
                // max(0, …): cos(pi/2) is a tiny negative number, and pow of a negative is NaN.
                let u = extent * pow(max(0, cos(t)), 2 / exponent)
                let v = extent * pow(max(0, sin(t)), 2 / exponent)
                let point = NSPoint(x: corner.x + ex * (extent - u), y: corner.y + ey * (extent - v))
                if first {
                    path.move(to: point)
                    first = false
                } else {
                    path.line(to: point)
                }
            }
        }
        path.close()
        return path
    }

    /// The glyph rendered white into its own transparent bitmap of the full canvas size.
    static func whiteGlyph(pixels: Int, in body: NSRect) -> NSBitmapImageRep {
        let size = CGFloat(pixels)
        let canvas = NSRect(x: 0, y: 0, width: size, height: size)
        let targetWidth = size * 0.5
        for name in symbolNames {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { continue }
            let configured = base.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: targetWidth, weight: .medium)
            ) ?? base
            let natural = configured.size
            guard natural.width > 0, natural.height > 0 else { continue }
            let scale = targetWidth / natural.width
            let glyphSize = NSSize(width: targetWidth, height: natural.height * scale)
            let rect = NSRect(
                x: (body.midX - glyphSize.width / 2).rounded(),
                y: (body.midY - glyphSize.height / 2).rounded(),
                width: glyphSize.width, height: glyphSize.height
            )
            let rep = bitmap(pixels: pixels)
            draw(into: rep) {
                NSColor.clear.set()
                canvas.fill(using: .copy)
                configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                // Template symbols draw black; keep their alpha and replace the colour.
                NSColor.white.set()
                canvas.fill(using: .sourceAtop)
            }
            if coverage(rep) > 0.01 {
                glyphSource = "SF Symbol \(name)"
                return rep
            }
        }
        glyphSource = "drawn fallback gauge"
        let rep = bitmap(pixels: pixels)
        draw(into: rep) {
            NSColor.clear.set()
            canvas.fill(using: .copy)
            drawFallbackGauge(center: NSPoint(x: body.midX, y: body.midY - size * 0.04), radius: targetWidth / 2)
        }
        guard coverage(rep) > 0.01 else { fail("glyph rendering produced an empty image at \(pixels) px") }
        return rep
    }

    /// Arc with a needle and hub, in white, for systems without any of the symbols.
    static func drawFallbackGauge(center: NSPoint, radius: CGFloat) {
        NSColor.white.set()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius * 0.85, startAngle: 200, endAngle: -20, clockwise: true)
        arc.lineWidth = radius * 0.16
        arc.lineCapStyle = .round
        arc.stroke()
        let angle = CGFloat(55) * .pi / 180
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: NSPoint(x: center.x + cos(angle) * radius * 0.62, y: center.y + sin(angle) * radius * 0.62))
        needle.lineWidth = radius * 0.11
        needle.lineCapStyle = .round
        needle.stroke()
        let hub = radius * 0.13
        NSBezierPath(ovalIn: NSRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)).fill()
    }

    /// Fraction of sampled pixels (at most a 128 x 128 grid) with visible opacity; detects a
    /// symbol that resolved but drew nothing.
    static func coverage(_ rep: NSBitmapImageRep) -> Double {
        let width = rep.pixelsWide, height = rep.pixelsHigh
        let step = max(1, max(width, height) / 128)
        var sampled = 0, opaque = 0
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                sampled += 1
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { opaque += 1 }
            }
        }
        return Double(opaque) / Double(max(1, sampled))
    }
}
