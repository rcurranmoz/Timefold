import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), count: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let count = SharedMemoriesManager.shared.readMemoryCount()
        completion(SimpleEntry(date: Date(), count: count))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let count = SharedMemoriesManager.shared.readMemoryCount()
        let currentDate = Date()
        let entry = SimpleEntry(date: currentDate, count: count)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let count: Int
}

struct TimefoldWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(entry: entry)
            case .systemMedium, .systemLarge:
                MediumWidgetView(entry: entry)
            case .accessoryCircular:
                AccessoryCircularView(entry: entry)
            case .accessoryRectangular:
                AccessoryRectangularView(entry: entry)
            default:
                SmallWidgetView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            if family != .accessoryCircular && family != .accessoryRectangular {
                if let image = SharedMemoriesManager.shared.readWidgetThumbnail() {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
    }
}

struct SmallWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .blur(radius: 20)
            }

            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(entry.count)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(entry.count == 1 ? "memory from today" : "memories from today")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                }
                .padding(14)
            }
        }
    }
}

struct MediumWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                .blur(radius: 20)
            }

            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(entry.count)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(entry.count == 1 ? "memory from today" : "memories from today")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                }
                .padding(14)
            }
        }
    }
}

struct AccessoryCircularView: View {
    let entry: SimpleEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(entry.count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

struct AccessoryRectangularView: View {
    let entry: SimpleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2.weight(.semibold))
                Text("Timefold")
                    .font(.caption2.weight(.semibold))
            }
            Text("\(entry.count) \(entry.count == 1 ? "memory" : "memories")")
                .font(.headline.weight(.bold))
                .minimumScaleFactor(0.7)
            Text("from today in past years")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimefoldWidget: Widget {
    let kind: String = "TimefoldWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TimefoldWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Timefold")
        .description("See how many memories you have from today")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
