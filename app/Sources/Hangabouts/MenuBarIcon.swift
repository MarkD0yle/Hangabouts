import AppKit

/// Draws the menu bar icon in code. The icon is Snuffler's burrow: the hole he drops out of.
/// - Resting: his eyes and nose peek out of the hole.
/// - Hanging: the hole is empty, and the swing's rope runs from it down to the creature panel.
/// The art is 26 pt wide, as large as the menu bar's height allows, in an image as tall as the menu bar.
/// Coordinates below are in a 100×100 grid, y down. The hole (not the grid) is centred vertically.
enum MenuBarIcon {
    static let artSize: CGFloat = 26
    private static let holeCentreY: CGFloat = 54

    private static let soil = color(0xA9824F)
    private static let soilLight = color(0xC7A06A)
    private static let soilEdge = color(0x4A2F1A)
    private static let dark = color(0x1A0E06)
    private static let fur = color(0xEDB547)

    // The hole: a mound of soil with a dark opening, seen from slightly above.
    private static let mound = oval(50, 54, 47, 37)
    private static let moundInner = oval(50, 54, 42.5, 32.5)
    private static let opening = oval(50, 57, 30, 21)

    /// Resting: Snuffler is at home. His uneven eyes and his nose show in the dark.
    static func resting(barHeight: CGFloat) -> NSImage {
        image(barHeight: barHeight) { _ in
            drawHole()

            // Big eye (the monocle eye) and small eye.
            NSColor.white.setFill()
            NSBezierPath(ovalIn: circle(40, 53, 9.5)).fill()
            NSBezierPath(ovalIn: circle(61, 54, 6.5)).fill()
            dark.setFill()
            NSBezierPath(ovalIn: circle(42, 54.5, 5)).fill()
            NSBezierPath(ovalIn: circle(62, 55, 3.4)).fill()

            // The tip of his snout rests on the front lip of the hole.
            soilEdge.setFill()
            NSBezierPath(ovalIn: oval(51, 76, 12.5, 11)).fill()
            fur.setFill()
            NSBezierPath(ovalIn: oval(51, 76, 9, 7.5)).fill()
            dark.setFill()
            NSBezierPath(ovalIn: oval(51, 79, 5, 3.6)).fill()
        }
    }

    /// Hanging: the empty hole, with the swing's rope running from inside it to the bottom of the
    /// menu bar, where it meets the ropes drawn by the creature panel. `ropeWidth` is in points.
    static func hanging(barHeight: CGFloat, ropeWidth: CGFloat) -> NSImage {
        image(barHeight: barHeight) { bottom in
            drawHole()

            // The rope: two strands side by side, from inside the hole down to the bottom edge.
            let width = max(ropeWidth, 2) * 100 / artSize
            let rope = NSRect(x: 50 - width / 2, y: 58, width: width, height: bottom - 58)
            let strands = NSGradient(colorsAndLocations:
                (color(0x8A6A3A), 0), (color(0xE2C894), 0.22), (color(0x8A6A3A), 0.5), (color(0xE2C894), 0.72), (color(0x7A5C30), 1))
            strands?.draw(in: rope, angle: 0)

            // Front lip of the hole, redrawn over the rope so the rope comes out from inside.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 58, width: 100, height: 60)).addClip()
            drawRim()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: - The hole

    private static func drawHole() {
        // A few crumbs of soil thrown up around it.
        soil.setFill()
        NSBezierPath(ovalIn: circle(8, 22, 4.5)).fill()
        NSBezierPath(ovalIn: circle(92, 20, 3.6)).fill()

        drawRim()

        // The opening: dark, with a lighter far wall so it reads as deep.
        dark.setFill()
        NSBezierPath(ovalIn: opening).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: opening).addClip()
        color(0x4A2E16).setFill()
        NSBezierPath(ovalIn: oval(50, 40, 30, 12)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The ring of soil around the opening. Drawn with the opening cut out of it.
    private static func drawRim() {
        let outer = NSBezierPath(ovalIn: mound)
        outer.append(NSBezierPath(ovalIn: opening))
        outer.windingRule = .evenOdd
        soilEdge.setFill()
        outer.fill()

        let inner = NSBezierPath(ovalIn: moundInner)
        inner.append(NSBezierPath(ovalIn: oval(50, 57, 33.5, 24.5)))
        inner.windingRule = .evenOdd
        NSGradient(starting: soilLight, ending: soil)?.draw(in: inner, angle: -90)
    }

    // MARK: - Helpers

    /// `draw` works in the 100×100 grid. Its argument is the y of the image's bottom edge in that grid.
    private static func image(barHeight: CGFloat, draw: @escaping (CGFloat) -> Void) -> NSImage {
        let height = max(barHeight, artSize)
        let image = NSImage(size: NSSize(width: artSize, height: height), flipped: true) { _ in
            let unit = artSize / 100
            let top = height / 2 - holeCentreY * unit
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
