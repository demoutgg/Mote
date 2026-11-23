// 内存回收：窗口关掉后我们自己的堆已经清空，但空闲页仍挂在 malloc 里，
// 主动还一次给系统，让长会话的占用尽量贴近刚启动时的基线。
import Darwin

enum MemoryPressure {
    static func relieve() {
        malloc_zone_pressure_relief(nil, 0)
    }
}
