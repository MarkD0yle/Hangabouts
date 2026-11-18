import AppKit

/// Draws the menu bar icon in code. The icon is Snuffler's burrow: the hole he drops out of.
/// - Resting: his eyes and nose peek out of the hole.
/// - Hanging: the hole is empty, and the swing's rope runs from it down to the creature panel.
/// The art is 26 pt wide, as large as the menu bar's height allows, in an image as tall as the menu bar.
/// Coordinates below are in a 100×100 grid, y down. The hole (not the grid) is centred vertically.
/// Reference drawings with the same grid: design/burrow-icon-resting.svg and design/burrow-icon-hanging.svg.
enum MenuBarIcon {
    static let artSize: CGFloat = 26
    private static let holeCentreY: CGFloat = 54

    private static let soil = color(0xA9824F)
    private static let soilLight = color(0xC7A06A)
    private static let soilDark = color(0x8E6A3E)
    private static let soilEdge = color(0x4A2F1A)
    private static let pebble = color(0x8B8478)
    private static let dark = color(0x1A0E06)
    private static let fur = color(0xEDB547)

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

            // The rope shows inside the opening and below the mound, but not over the front lip,
            // so it comes out from inside the hole. (Clipping, not redrawing the lip, avoids a seam.)
            NSGraphicsContext.saveGraphicsState()
            let visible = NSBezierPath(rect: NSRect(x: -10, y: -10, width: 120, height: bottom + 20))
            visible.append(shape(moundPoints))
            visible.append(shape(openingPoints))
            visible.windingRule = .evenOdd
            visible.addClip()
            drawRope(width: max(ropeWidth, 2) * 100 / artSize, top: 58, bottom: bottom)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: - The hole

    private static func drawHole() {
        drawSoil()
        drawRim()

        // The opening: dark, with a lighter far wall so it reads as deep.
        let opening = shape(openingPoints)
        dark.setFill()
        opening.fill()
        NSGraphicsContext.saveGraphicsState()
        opening.addClip()
        color(0x4A2E16).setFill()
        NSBezierPath(ovalIn: oval(50, 40, 30, 12)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Loose soil thrown up around the hole: crumbs, two outlined clods and two grey pebbles.
    /// The smallest crumbs are under 1 px at real size. If they blur into a halo, drop them and keep the clods.
    private static func drawSoil() {
        let crumbs: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
            (8, 22, 4.5, soil), (15, 15, 2.2, soilDark), (92, 20, 3.6, soil), (84, 13, 2, soil),
            (14, 88, 2.6, soil), (86, 89, 3, soil), (76, 95, 1.8, soilDark), (25, 94, 1.6, soilDark),
        ]
        for (x, y, r, c) in crumbs {
            c.setFill()
            NSBezierPath(ovalIn: circle(x, y, r)).fill()
        }

        for (points, fill) in [([0.5, 66, 4, 61.5, 8.5, 63, 9.5, 68, 5, 71, 1, 70] as [CGFloat], soil),
                               ([90.5, 71, 95, 66, 99.5, 69, 98.5, 74.5, 93, 75.5] as [CGFloat], soilLight)] {
            let clod = shape(points)
            clod.lineWidth = 1.6
            clod.lineJoinStyle = .round
            fill.setFill()
            clod.fill()
            soilEdge.setStroke()
            clod.stroke()
        }

        pebble.setFill()
        NSBezierPath(ovalIn: oval(96, 44, 2.6, 2)).fill()
        NSBezierPath(ovalIn: oval(3.5, 44, 2, 1.6)).fill()
    }

    /// The lumpy ring of soil around the opening. Drawn with the opening cut out of it.
    private static func drawRim() {
        let outer = shape(moundPoints)
        outer.append(shape(openingPoints))
        outer.windingRule = .evenOdd
        soilEdge.setFill()
        outer.fill()

        let inner = shape(moundInnerPoints)
        inner.append(shape(rimInnerHolePoints))
        inner.windingRule = .evenOdd
        NSGradient(starting: soilLight, ending: soil)?.draw(in: inner, angle: -90)
    }

    // MARK: - The rope

    /// Twisted rope: diagonal bands, shaded so it looks round, with a thin dark line down each side.
    /// Same colours as the ropes on the creature panel. `width` is in grid units.
    private static func drawRope(width: CGFloat, top: CGFloat, bottom: CGFloat) {
        let left = 50 - width / 2
        let rope = NSRect(x: left, y: top, width: width, height: bottom - top)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rope).addClip()

        // Twist: dark bands at -38°, one every 0.7 × the rope width, on the light strand colour.
        color(0xCCA86B).setFill()
        rope.fill()
        let twist = NSAffineTransform()
        twist.translateX(by: left, yBy: top)
        twist.rotate(byDegrees: -38)
        twist.concat()
        color(0x8F6C3A).setFill()
        let pitch = width * 0.7
        let reach = (bottom - top) + width * 2   // far enough to cover the rope once rotated
        var y = -reach
        while y < reach {
            NSRect(x: -reach, y: y, width: reach * 2, height: pitch * 0.47).fill()
            y += pitch
        }
        NSGraphicsContext.restoreGraphicsState()

        // Roundness: light on the left, dark on the right.
        let round = NSGradient(colors: [
            color(0xFFF4DC, alpha: 0.35), color(0xFFF4DC, alpha: 0),
            color(0x2B1A0C, alpha: 0), color(0x2B1A0C, alpha: 0.45),
        ], atLocations: [0, 0.35, 0.7, 1], colorSpace: .sRGB)
        round?.draw(in: rope, angle: 0)

        // Edges.
        let edge = max(width * 0.12, 0.9)
        soilEdge.setStroke()
        for x in [rope.minX, rope.maxX] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: top))
            line.line(to: NSPoint(x: x, y: bottom))
            line.lineWidth = edge
            line.stroke()
        }
    }

    // MARK: - Outlines (copied from the SVGs in design/, as x, y pairs)

    private static let moundPoints: [CGFloat] = [
        100.21, 54.00, 99.71, 57.42, 98.70, 60.76, 97.18, 63.95, 94.97, 66.89, 92.18, 69.48, 89.34, 71.88, 86.99, 74.39,
        85.06, 77.16, 82.97, 79.95, 80.19, 82.32, 76.72, 84.04, 72.96, 85.31, 69.25, 86.50, 65.59, 87.72, 61.83, 88.76,
        57.93, 89.42, 53.98, 89.83, 50.00, 90.24, 45.92, 90.67, 41.76, 90.77, 37.68, 90.18, 33.83, 88.98, 30.06, 87.66,
        26.11, 86.58, 21.90, 85.60, 17.79, 84.22, 14.32, 82.09, 11.71, 79.29, 9.78, 76.17, 8.30, 72.95, 7.28, 69.68,
        6.89, 66.35, 6.94, 63.08, 6.88, 59.99, 6.24, 57.01, 5.21, 54.00, 4.54, 50.87, 4.80, 47.73, 5.87, 44.69,
        7.14, 41.72, 8.20, 38.66, 9.26, 35.48, 10.80, 32.39, 13.04, 29.59, 15.79, 27.07, 18.78, 24.71, 22.03, 22.56,
        25.70, 20.86, 29.75, 19.81, 33.90, 19.18, 37.90, 18.44, 41.78, 17.32, 45.79, 16.10, 50.00, 15.45, 54.25, 15.75,
        58.32, 16.86, 62.15, 18.30, 65.79, 19.84, 69.22, 21.55, 72.35, 23.53, 75.24, 25.62, 78.22, 27.53, 81.50, 29.21,
        84.89, 30.95, 87.88, 33.12, 90.16, 35.75, 91.99, 38.58, 93.96, 41.40, 96.27, 44.24, 98.47, 47.27, 99.88, 50.56,
    ]
    private static let openingPoints: [CGFloat] = [
        79.87, 57.00, 79.59, 58.81, 78.94, 60.57, 78.17, 62.28, 77.53, 64.02, 76.99, 65.81, 76.25, 67.61, 75.08, 69.29,
        73.48, 70.79, 71.65, 72.15, 69.73, 73.46, 67.71, 74.70, 65.49, 75.78, 63.06, 76.60, 60.51, 77.21, 57.92, 77.69,
        55.29, 78.02, 52.63, 78.07, 50.00, 77.74, 47.48, 77.16, 45.07, 76.57, 42.66, 76.16, 40.18, 75.88, 37.66, 75.52,
        35.22, 74.92, 32.91, 74.09, 30.70, 73.10, 28.59, 71.99, 26.68, 70.70, 25.09, 69.21, 23.80, 67.59, 22.62, 65.94,
        21.42, 64.28, 20.30, 62.57, 19.57, 60.76, 19.39, 58.87, 19.65, 57.00, 20.05, 55.17, 20.42, 53.35, 20.84, 51.53,
        21.55, 49.75, 22.61, 48.06, 23.92, 46.46, 25.40, 44.94, 27.08, 43.54, 29.07, 42.35, 31.31, 41.41, 33.62, 40.63,
        35.81, 39.80, 37.88, 38.81, 39.99, 37.74, 42.28, 36.83, 44.76, 36.21, 47.35, 35.83, 50.00, 35.59, 52.69, 35.48,
        55.39, 35.61, 58.03, 36.03, 60.56, 36.69, 63.02, 37.46, 65.43, 38.29, 67.69, 39.31, 69.63, 40.62, 71.17, 42.18,
        72.46, 43.81, 73.77, 45.35, 75.19, 46.82, 76.62, 48.31, 77.81, 49.92, 78.67, 51.62, 79.30, 53.38, 79.73, 55.18,
    ]
    private static let moundInnerPoints: [CGFloat] = [
        95.21, 54.00, 94.77, 57.00, 93.89, 59.92, 92.56, 62.72, 90.62, 65.30, 88.16, 67.61, 85.66, 69.74, 83.54, 71.96,
        81.76, 74.38, 79.83, 76.81, 77.30, 78.88, 74.17, 80.40, 70.79, 81.54, 67.44, 82.60, 64.13, 83.68, 60.72, 84.59,
        57.19, 85.18, 53.61, 85.53, 50.00, 85.87, 46.31, 86.22, 42.56, 86.28, 38.87, 85.76, 35.38, 84.72, 31.98, 83.56,
        28.42, 82.58, 24.66, 81.68, 21.00, 80.43, 17.88, 78.56, 15.52, 76.13, 13.74, 73.42, 12.35, 70.62, 11.38, 67.77,
        10.96, 64.87, 10.93, 62.01, 10.82, 59.28, 10.24, 56.66, 9.37, 54.00, 8.81, 51.24, 9.07, 48.48, 10.02, 45.81,
        11.16, 43.19, 12.16, 40.51, 13.16, 37.74, 14.60, 35.04, 16.64, 32.59, 19.12, 30.39, 21.83, 28.33, 24.77, 26.45,
        28.07, 24.96, 31.71, 24.01, 35.44, 23.41, 39.05, 22.76, 42.57, 21.80, 46.20, 20.77, 50.00, 20.23, 53.83, 20.49,
        57.51, 21.42, 60.99, 22.64, 64.30, 23.96, 67.42, 25.43, 70.28, 27.14, 72.93, 28.96, 75.63, 30.64, 78.58, 32.14,
        81.62, 33.71, 84.29, 35.64, 86.35, 37.95, 88.01, 40.45, 89.76, 42.93, 91.78, 45.44, 93.70, 48.11, 94.92, 50.99,
    ]
    private static let rimInnerHolePoints: [CGFloat] = [
        83.36, 57.00, 83.05, 59.11, 82.32, 61.17, 81.46, 63.16, 80.75, 65.18, 80.14, 67.28, 79.32, 69.38, 78.01, 71.34,
        76.22, 73.09, 74.17, 74.68, 72.03, 76.20, 69.78, 77.66, 67.30, 78.91, 64.58, 79.87, 61.74, 80.58, 58.84, 81.14,
        55.91, 81.52, 52.94, 81.58, 50.00, 81.20, 47.19, 80.52, 44.49, 79.84, 41.81, 79.36, 39.04, 79.03, 36.22, 78.61,
        33.49, 77.91, 30.91, 76.94, 28.45, 75.78, 26.09, 74.48, 23.96, 72.98, 22.18, 71.25, 20.74, 69.36, 19.43, 67.43,
        18.09, 65.50, 16.84, 63.50, 16.02, 61.38, 15.82, 59.19, 16.11, 57.00, 16.56, 54.86, 16.96, 52.74, 17.44, 50.62,
        18.23, 48.54, 19.41, 46.57, 20.88, 44.70, 22.53, 42.93, 24.41, 41.30, 26.62, 39.90, 29.13, 38.81, 31.71, 37.90,
        34.16, 36.93, 36.47, 35.77, 38.82, 34.53, 41.38, 33.47, 44.15, 32.74, 47.05, 32.30, 50.00, 32.02, 53.00, 31.90,
        56.02, 32.04, 58.96, 32.54, 61.79, 33.31, 64.54, 34.20, 67.23, 35.17, 69.76, 36.36, 71.92, 37.89, 73.64, 39.71,
        75.08, 41.61, 76.54, 43.41, 78.13, 45.12, 79.72, 46.86, 81.05, 48.73, 82.02, 50.73, 82.71, 52.78, 83.20, 54.88,
    ]

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

    /// A closed polygon through x, y pairs.
    private static func shape(_ xy: [CGFloat]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: xy[0], y: xy[1]))
        for i in stride(from: 2, to: xy.count - 1, by: 2) {
            path.line(to: NSPoint(x: xy[i], y: xy[i + 1]))
        }
        path.close()
        return path
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSRect {
        NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
    }

    private static func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSRect {
        NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
    }

    private static func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }
}
