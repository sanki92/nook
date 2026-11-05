import CoreGraphics
import Foundation

struct Cell: Hashable {
    var column: Int
    var row: Int
}

struct SavedSlot: Equatable {
    var display: UInt32
    var cell: Cell
}

struct SlotGrid {
    let visibleFrame: CGRect

    var columns: Int { Int(((visibleFrame.width - WidgetMetrics.margin * 2) / WidgetMetrics.cell).rounded(.down)) }
    var rows: Int { Int(((visibleFrame.height - WidgetMetrics.margin * 2) / WidgetMetrics.cell).rounded(.down)) }

    func area(_ cell: Cell, _ size: WidgetSize) -> CGRect {
        let width = CGFloat(size.columns) * WidgetMetrics.cell
        let height = CGFloat(size.rows) * WidgetMetrics.cell
        let x = visibleFrame.minX + WidgetMetrics.margin + CGFloat(cell.column) * WidgetMetrics.cell
        let top = visibleFrame.maxY - WidgetMetrics.margin - CGFloat(cell.row) * WidgetMetrics.cell
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    func frame(_ cell: Cell, _ size: WidgetSize) -> CGRect {
        area(cell, size).insetBy(dx: WidgetMetrics.margin, dy: WidgetMetrics.margin)
    }

    func isFree(_ cell: Cell, _ size: WidgetSize, taken: [CGRect]) -> Bool {
        guard cell.column >= 0, cell.row >= 0,
              cell.column + size.columns <= columns,
              cell.row + size.rows <= rows else { return false }
        let block = area(cell, size).insetBy(dx: 1, dy: 1)
        return !taken.contains { $0.intersects(block) }
    }

    func nearestFree(toTopLeft point: CGPoint, _ size: WidgetSize, taken: [CGRect]) -> Cell? {
        var best: (cell: Cell, distance: CGFloat)?
        for row in 0..<max(rows, 0) {
            for column in 0..<max(columns, 0) {
                let cell = Cell(column: column, row: row)
                guard isFree(cell, size, taken: taken) else { continue }
                let rect = frame(cell, size)
                let distance = hypot(rect.minX - point.x, rect.maxY - point.y)
                if best == nil || distance < best!.distance { best = (cell, distance) }
            }
        }
        return best?.cell
    }
}

struct Display {
    var id: UInt32
    var grid: SlotGrid
    var isMain: Bool
}

func resolvePlacement(saved: SavedSlot?, size: WidgetSize, displays: [Display], taken: [CGRect]) -> SavedSlot {
    if let saved, let display = displays.first(where: { $0.id == saved.display }) {
        if display.grid.isFree(saved.cell, size, taken: taken) { return saved }
        let rect = display.grid.frame(saved.cell, size)
        let origin = CGPoint(x: rect.minX, y: rect.maxY)
        if let cell = display.grid.nearestFree(toTopLeft: origin, size, taken: taken) {
            return SavedSlot(display: display.id, cell: cell)
        }
    }
    guard let main = displays.first(where: \.isMain) ?? displays.first else {
        return SavedSlot(display: 0, cell: Cell(column: 0, row: 0))
    }
    let rect = main.grid.frame(Cell(column: 0, row: 0), size)
    let origin = CGPoint(x: rect.minX, y: rect.maxY)
    if let cell = main.grid.nearestFree(toTopLeft: origin, size, taken: taken) {
        return SavedSlot(display: main.id, cell: cell)
    }
    return SavedSlot(display: main.id, cell: Cell(column: 0, row: 0))
}
