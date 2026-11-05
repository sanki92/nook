import CoreGraphics
import Foundation

enum WidgetMetrics {
    static let cell: CGFloat = 180
    static let margin: CGFloat = 8
    static let tileInset: CGFloat = 6
    static let tileGap: CGFloat = 6
}

enum WidgetSize: String, CaseIterable {
    case medium, large, extraLarge

    var columns: Int { self == .extraLarge ? 4 : 2 }
    var rows: Int { self == .medium ? 1 : 2 }
    var points: CGSize {
        CGSize(width: CGFloat(columns) * WidgetMetrics.cell - WidgetMetrics.margin * 2,
               height: CGFloat(rows) * WidgetMetrics.cell - WidgetMetrics.margin * 2)
    }
    var title: String {
        switch self {
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
    var maxTiles: Int {
        switch self {
        case .medium: return 1
        case .large: return 9
        case .extraLarge: return 12
        }
    }
}

func tileRects(count: Int, size: WidgetSize) -> [CGRect] {
    let full = CGRect(origin: .zero, size: size.points)
    if count <= 1 || size == .medium { return [full] }
    let inset = WidgetMetrics.tileInset, gap = WidgetMetrics.tileGap
    let width = full.width - inset * 2
    let height = full.height - inset * 2

    if count == 3 && size == .extraLarge {
        let w = (width - gap) / 2, h = (height - gap) / 2
        return [
            CGRect(x: inset, y: inset, width: w, height: height),
            CGRect(x: inset + w + gap, y: inset, width: w, height: h),
            CGRect(x: inset + w + gap, y: inset + h + gap, width: w, height: h),
        ]
    }

    let rows: [Int]
    switch size {
    case .large:
        switch count {
        case 2: rows = [1, 1]
        case 3: rows = [1, 2]
        case 4: rows = [2, 2]
        case 5: rows = [2, 3]
        case 6: rows = [3, 3]
        case 7: rows = [2, 2, 3]
        case 8: rows = [2, 3, 3]
        default: rows = [3, 3, 3]
        }
    default:
        switch count {
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

func tileGeometry(size: CGSize) -> TileGeometry {
    let sceneWidth = 86.0
    let compact = size.width < 158 || size.height < 114
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
