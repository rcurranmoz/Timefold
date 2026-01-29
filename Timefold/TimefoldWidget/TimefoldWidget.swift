import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), count: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let count = SharedMemoriesManager.shared.readMemoryCount()
        let entry = SimpleEntry(date: Date(), count: count)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let count = SharedMemoriesManager.shared.readMemoryCount()
        let currentDate = Date()
        let entry = SimpleEntry(date: currentDate, count: count)
        
        // Refresh every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let count: Int
}

struct TimefoldWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.white)
            
            if entry.count > 0 {
                Text("\(entry.count)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(entry.count == 1 ? "memory" : "memories")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                
                Text("from today")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text("No memories")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("from today")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

struct TimefoldWidget: Widget {
    let kind: String = "TimefoldWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TimefoldWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Timefold")
        .description("See how many memories you have from today")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
