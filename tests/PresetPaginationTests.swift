import Foundation

@main
struct PresetPaginationTests {
    static func main() {
        var pages = PresetPagination(itemCount: 48, pageSize: 3)
        precondition(pages.pageCount == 16 && pages.visibleRange == 0..<3)
        var visited = Set<Int>()
        for _ in 0..<pages.pageCount {
            visited.formUnion(pages.visibleRange)
            pages.next()
        }
        precondition(visited == Set(0..<48), "Every preset must be reachable, including the last page")
        precondition(pages.page == 15 && pages.visibleRange == 45..<48, "Next clamps at the last page")
        pages.move(to: -99)
        pages.previous()
        precondition(pages.page == 0, "Previous and negative jumps clamp at the first page")
        pages.move(to: 4)
        let anchor = pages.visibleRange.lowerBound
        pages.update(itemCount: 48, pageSize: 5)
        precondition(pages.visibleRange.contains(anchor), "Resize must retain the first previously visible item")
        pages.update(itemCount: 2, pageSize: 5, resetPage: true)
        precondition(pages.page == 0 && pages.visibleRange == 0..<2, "Filtering resets to the first result page")
        pages.update(itemCount: 0, pageSize: 5, resetPage: true)
        pages.next(); pages.previous(); pages.move(to: 30); pages.reveal(index: 9)
        precondition(pages.page == 0 && pages.pageCount == 0 && pages.visibleRange.isEmpty, "Empty results never create an invalid page")
        pages.update(itemCount: 48, pageSize: 3)
        pages.reveal(index: 47)
        precondition(pages.page == 15 && pages.visibleRange.contains(47), "Locate current preset must show its actual page")
        pages.update(itemCount: 48, pageSize: 8)
        precondition(pages.visibleRange.contains(45) && pages.pageCount == 6)
        pages.move(to: Int.max)
        precondition(pages.visibleRange == 40..<48)
        let partial = PresetPagination(itemCount: 10, pageSize: 4, page: 2)
        precondition(partial.visibleRange == 8..<10 && partial.pageCount == 3, "Final partial page cannot leak out-of-range indices")
        precondition(PresetPagination.pageSize(availableHeight: 0) == 3)
        precondition(PresetPagination.pageSize(availableHeight: 202) == 3)
        precondition(PresetPagination.pageSize(availableHeight: 342) == 5)
        precondition(PresetPagination.pageSize(availableHeight: 10000) == 8)
        precondition(PresetPagination.pageSize(availableHeight: .nan) == 3)
        precondition(PresetPagination(itemCount: -1, pageSize: 0).visibleRange.isEmpty)
        print("PASS: all 48 presets reachable; page bounds, partial/empty pages, filter reset, resize anchor and locate-current")
    }
}
