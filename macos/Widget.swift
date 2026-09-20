import SwiftUI
import WidgetKit

struct PulseEntry: TimelineEntry {
    let date: Date
    let snapshot: PulseSnapshot
}
struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry { PulseEntry(date: Date(), snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(PulseEntry(date: Date(), snapshot: .read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [PulseEntry(date: now, snapshot: .read())], policy: .after(now.addingTimeInterval(300))))
    }
}
struct WidgetContent: View {
    let entry: PulseEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        PulseCard(snapshot: entry.snapshot, compact: family == .systemSmall, expanded: family == .systemLarge)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red:0.055,green:0.11,blue:0.14),Color(red:0.04,green:0.065,blue:0.09)],startPoint:.topLeading,endPoint:.bottomTrailing)
            }
            .widgetURL(URL(string: "codexpulse://dashboard"))
            .environment(\.locale,Locale(identifier:"zh_CN"))
    }
}
@main
struct CodexPulseWidget: Widget {
    let kind = "CodexPulseWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProvider()) { entry in WidgetContent(entry: entry) }
            .configurationDisplayName("Codex Pulse")
            .description("Codex 剩余额度、消耗速度、重置时间与本机任务状态。")
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge])
    }
}
