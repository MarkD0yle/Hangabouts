import AppKit

/// Draws the menu bar icon in code, so the resting head and the burrow he hangs from line up exactly.
/// The art is 18×18 pt, centred in an image as tall as the menu bar.
/// Coordinates below are in a 100×100 grid, y down, matching design/snuffler-real3d.html.
enum MenuBarIcon {
    static let artSize: CGFloat = 18

    private static let outline = color(0x5A3812)
    private static let fur = color(0xEDB547)
    private static let furDark = color(0xC98A2B)
    private static let soil = color(0x9C7A4E)
    private static let soilEdge = color(0x4A2F1A)

    /// Resting: Snuffler's head in profile.
    static func resting(barHeight: CGFloat) -> NSImage {
        image(barHeight: barHeight) { _ in
            let ear = NSBezierPath(ovalIn: circle(20, 20, 9))
            let head = NSBezierPath(ovalIn: circle(38, 44, 27))
            let snout = NSBezierPath()
            snout.move(to: NSPoint(x: 52, y: 24))
            snout.curve(to: NSPoint(x: 90, y: 80), controlPoint1: NSPoint(x: 74, y: 30), controlPoint2: NSPoint(x: 88, y: 52))
            snout.curve(to: NSPoint(x: 76, y: 82), controlPoint1: NSPoint(x: 91, y: 90), controlPoint2: NSPoint(x: 78, y: 92))
            snout.curve(to: NSPoint(x: 48, y: 62), controlPoint1: NSPoint(x: 72, y: 66), controlPoint2: NSPoint(x: 64, y: 60))
            snout.close()

            // Dark outline first, then the fills on top.
            outline.set()
            for path in [ear, head, snout] {
                path.lineWidth = 9
                path.lineJoinStyle = .round
                path.fill()
                path.stroke()
            }
            fur.setFill()
            ear.fill()
            head.fill()
            furDark.setFill()
            snout.fill()

            let eye = NSBezierPath(ovalIn: circle(40, 40, 12))
            color(0xFFFDF6).setFill()
            eye.fill()
            outline.setStroke()
            eye.lineWidth = 4
            eye.stroke()
            color(0x231A12).setFill()
            NSBezierPath(ovalIn: circle(43, 41, 6)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: circle(45.5, 38, 2.4)).fill()
            color(0x2A170E).setFill()
            NSBezierPath(ovalIn: circle(83, 82, 6.5)).fill()
        }
    }

    /// Hanging: his empty burrow, with the swing's rope running from the hole to the bottom of the
    /// menu bar, where it meets the ropes drawn by the creature panel. `ropeWidth` is in points.
    static func hanging(barHeight: CGFloat, ropeWidth: CGFloat) -> NSImage {
        image(barHeight: barHeight) { bottom in
            soilEdge.setFill()
            NSBezierPath(ovalIn: oval(50, 56, 46, 27)).fill()
            soil.setFill()
            NSBezierPath(ovalIn: oval(50, 56, 42, 23)).fill()
            color(0x1E1108).setFill()
            NSBezierPath(ovalIn: oval(50, 57, 31, 15)).fill()
            soil.setFill()
            NSBezierPath(ovalIn: circle(10, 26, 5)).fill()
            NSBezierPath(ovalIn: circle(89, 25, 4)).fill()

            // The rope: two strands side by side, from inside the hole down to the bottom edge.
            let width = max(ropeWidth, 2) * 100 / artSize
            let rope = NSRect(x: 50 - width / 2, y: 57, width: width, height: bottom - 57)
            let shading = NSGradient(colorsAndLocations:
                (color(0x8A6A3A), 0), (color(0xD9BE8A), 0.22), (color(0x8A6A3A), 0.5), (color(0xD9BE8A), 0.72), (color(0x7A5C30), 1))
            shading?.draw(in: rope, angle: 0)

            // Front lip of the burrow, over the rope.
            let lip = NSBezierPath()
            lip.move(to: NSPoint(x: 6, y: 56))
            lip.curve(to: NSPoint(x: 94, y: 56), controlPoint1: NSPoint(x: 6, y: 89), controlPoint2: NSPoint(x: 94, y: 89))
            lip.lineCapStyle = .round
            soilEdge.setStroke()
            lip.lineWidth = 20
            lip.stroke()
            soil.setStroke()
            lip.lineWidth = 12
            lip.stroke()
        }
    }

    // MARK: - Helpers

    /// `draw` works in the 100×100 grid. Its argument is the y of the image's bottom edge in that grid.
    private static func image(barHeight: CGFloat, draw: @escaping (CGFloat) -> Void) -> NSImage {
        let height = max(barHeight, artSize)
        let image = NSImage(size: NSSize(width: artSize, height: height), flipped: true) { _ in
            let unit = artSize / 100
            let top = (height - artSize) / 2
            let transform = NSAffineTransform()
            transform.translateX(by: 0, yBy: top)
            transform.scale(by: unit)
            transform.concat()
            draw((height - top) / unit)
            return true
        }
        image.isTemplate = false // the icon is coloured
        return image
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSRect {
        NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
    }

    private static func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSRect {
        NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
    }

    private static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}
