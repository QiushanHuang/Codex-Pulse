import Foundation

/// Page navigation is independent of the preset currently applied to the device.
struct PresetPagination: Equatable {
    private(set) var itemCount: Int
    private(set) var pageSize: Int
    private(set) var page: Int
    var pageCount: Int { itemCount == 0 ? 0 : (itemCount - 1) / pageSize + 1 }
    var visibleRange: Range<Int> {
        let start = min(itemCount, page * pageSize)
        return start..<(start + min(pageSize, itemCount - start))
    }
    init(itemCount: Int, pageSize: Int, page: Int = 0) {
        self.itemCount = max(0, itemCount)
        self.pageSize = min(8, max(3, pageSize))
        self.page = 0
        move(to: page)
    }
    mutating func update(itemCount: Int, pageSize: Int, resetPage: Bool = false) {
        let anchor = visibleRange.lowerBound
        self.itemCount = max(0, itemCount)
        self.pageSize = min(8, max(3, pageSize))
        move(to: resetPage ? 0 : anchor / self.pageSize)
    }
    mutating func move(to page: Int) { self.page = max(0, min(max(0, pageCount - 1), page)) }
    mutating func next() { if page < pageCount - 1 { page += 1 } }
    mutating func previous() { if page > 0 { page -= 1 } }
    mutating func reveal(index: Int) { move(to: max(0, min(max(0, itemCount - 1), index)) / pageSize) }
    /// Rows are 62 points tall with 8 points between them; the caller reserves fixed browser controls first.
    static func pageSize(availableHeight: Double) -> Int {
        guard availableHeight.isFinite else { return 3 }
        return Int(min(8, max(3, floor((availableHeight + 8) / 70))))
    }
}
