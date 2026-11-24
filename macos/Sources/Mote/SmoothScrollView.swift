// 鼠标滚轮的像素级滚动容器：系统对普通滚轮按整行（历史列表 54pt）翻页，观感一顿一顿。
// 只接管非精确增量（鼠标滚轮），触控板的 precise 增量仍交回系统处理。
import AppKit

final class SmoothScrollView: NSScrollView {
    /// 一格滚轮的位移；系统默认是整行 54pt，缩到约半行更跟手
    private static let wheelStep: CGFloat = 24

    override func scrollWheel(with event: NSEvent) {
        guard !event.hasPreciseScrollingDeltas,
              let documentView,
              event.scrollingDeltaY != 0
        else {
            super.scrollWheel(with: event)
            return
        }
        let limit = max(0, documentView.bounds.height - contentView.bounds.height)
        // 翻转的文档视图（表格、文本视图）向下滚对应原点增大，与 deltaY 符号相反
        let direction: CGFloat = documentView.isFlipped ? -1 : 1
        var origin = contentView.bounds.origin
        origin.y = min(max(0, origin.y + direction * event.scrollingDeltaY * Self.wheelStep), limit)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}
