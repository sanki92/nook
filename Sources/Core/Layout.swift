import CoreGraphics
import Foundation

enum WidgetMetrics {
    static let size = CGSize(width: 704, height: 344)
    static let inset: CGFloat = 10
    static let gap: CGFloat = 8
    static let fullSceneLimit = 8
    static let maxTiles = 12
}

func tileRects(count: Int) -> [CGRect] {
    let inset = WidgetMetrics.inset, gap = WidgetMetrics.gap
    let width = WidgetMetrics.size.width - inset * 2
    let height = WidgetMetrics.size.height - inset * 2

    if count == 3 {
        let w = (width - gap) / 2, h = (height - gap) / 2
        return [
            CGRect(x: inset, y: inset, width: w, height: height),
            CGRect(x: inset + w + gap, y: inset, width: w, height: h),
            CGRect(x: inset + w + gap, y: inset + h + gap, width: w, height: h),
        ]
    }

    let rows: [Int]
    switch count {
    case ...1: rows = [1]
    case 2: rows = [2]
    case 4: rows = [2, 2]
    case 5: rows = [2, 3]
    case 6: rows = [3, 3]
    case 7: rows = [3, 4]
    case 8: rows = [4, 4]
    case 9: rows = [3, 3, 3]
    case 10: rows = [3, 3, 4]
    case 11: rows = [3, 4, 4]
    default: rows = [4, 4, 4]
    }

    let h = (height - gap * CGFloat(rows.count - 1)) / CGFloat(rows.count)
    var rects: [CGRect] = []
    for (r, columns) in rows.enumerated() {
        let w = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        for c in 0..<columns {
            rects.append(CGRect(x: inset + CGFloat(c) * (w + gap), y: inset + CGFloat(r) * (h + gap), width: w, height: h))
        }
    }
    return rects
}

struct TileGeometry: Equatable {
    var pixel: Int
    var compact: Bool
    var canvasWidth: Int
    var canvasHeight: Int
    var offsetX: Int
    var offsetY: Int
    var nameFontSize: CGFloat
    var nameBottom: CGFloat
}

func tileGeometry(size: CGSize, tileCount: Int) -> TileGeometry {
    let sceneWidth = 86.0
    let compact = tileCount > WidgetMetrics.fullSceneLimit
    let tall = size.height > 200
    let nameHeight: CGFloat = compact ? 25 : (tall ? 42 : 26)
    let available = size.height - nameHeight

    let pixel = compact ? 2 : max(2, min(5, Int(size.width / 79), Int(available / 44)))
    let width = Int((size.width / CGFloat(pixel)).rounded(.up))
    let height = Int((size.height / CGFloat(pixel)).rounded(.up))
    let rows = Int((available / CGFloat(pixel)).rounded(.down))

    return TileGeometry(
        pixel: pixel,
        compact: compact,
        canvasWidth: width,
        canvasHeight: height,
        offsetX: compact ? (width - 32) / 2 : Int(((Double(width) - sceneWidth) / 2).rounded(.down)),
        offsetY: compact ? rows - 46 : rows - 47,
        nameFontSize: compact ? 12.5 : (tall ? 19 : 14),
        nameBottom: compact ? 7 : (tall ? 14 : 7))
}
