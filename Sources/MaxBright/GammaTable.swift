import CoreGraphics

/// A snapshot of a display's gamma (transfer) table.
struct GammaTable {
    var red: [CGGammaValue]
    var green: [CGGammaValue]
    var blue: [CGGammaValue]

    /// macOS clamps tables written at the display's full capacity (1024 entries) to SDR white, but keeps values
    /// above 1.0 in 256-entry tables, so every read and write uses this size.
    private static let size: UInt32 = 256

    static func read(from display: CGDirectDisplayID) -> GammaTable? {
        var r = [CGGammaValue](repeating: 0, count: Int(size)), g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, size, &r, &g, &b, &count) == .success, count > 0 else { return nil }
        let n = Int(count)
        return GammaTable(red: Array(r[..<n]), green: Array(g[..<n]), blue: Array(b[..<n]))
    }

    @discardableResult
    func write(to display: CGDirectDisplayID) -> Bool {
        CGSetDisplayTransferByTable(display, UInt32(red.count), red, green, blue) == .success
    }

    var peak: CGGammaValue {
        max(red.max() ?? 0, green.max() ?? 0, blue.max() ?? 0)
    }

    func scaled(by factor: CGGammaValue) -> GammaTable {
        GammaTable(red: red.map { $0 * factor }, green: green.map { $0 * factor }, blue: blue.map { $0 * factor })
    }

    /// The table rescaled so it never maps past SDR white.
    func normalized() -> GammaTable {
        let peak = peak
        return peak > 1 ? scaled(by: 1 / peak) : self
    }

    func isClose(to other: GammaTable, tolerance: CGGammaValue = 0.002) -> Bool {
        func close(_ a: [CGGammaValue], _ b: [CGGammaValue]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
        }
        return close(red, other.red) && close(green, other.green) && close(blue, other.blue)
    }
}
