import WidgetKit
import SwiftUI
import UIKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), count: 0, photo: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        completion(Self.entry(for: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = Self.entry(for: context.family)
        // The count only changes when the calendar day rolls, so asking to be
        // woken hourly spent 24x the refresh budget to redraw the same number.
        completion(Timeline(entries: [entry], policy: .after(Self.nextMidnight(after: entry.date))))
    }

    /// Read the shared container once, here — not from the view body, which
    /// re-evaluates and would re-decode the JPEG every time inside an
    /// extension with a hard memory ceiling.
    private static func entry(for family: WidgetFamily) -> SimpleEntry {
        let count = SharedMemoriesManager.shared.readMemoryCount()
        // Accessory families draw no photo; don't pay to decode one.
        let photo = family.usesPhotoBackground ? SharedMemoriesManager.shared.readWidgetThumbnail() : nil
        return SimpleEntry(date: Date(), count: count, photo: photo)
    }

    private static func nextMidnight(after date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.nextDate(after: date,
                                 matching: DateComponents(hour: 0, minute: 0, second: 0),
                                 matchingPolicy: .nextTime)
            ?? calendar.date(byAdding: .hour, value: 1, to: date)!
    }
}

extension WidgetFamily {
    /// Accessory complications render monochrome on a system backdrop and
    /// never show the day's photo.
    var usesPhotoBackground: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return false
        default: return true
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let count: Int
    /// Decoded once per timeline entry, in the provider.
    let photo: UIImage?
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
            if family.usesPhotoBackground {
                if let image = entry.photo {
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
                LatentMark(monochrome: .primary)
                    .frame(height: 9)
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
                LatentMark(monochrome: .primary)
                    .frame(height: 9)
                Text("Latent")
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
    // Do not rename: WidgetKit persists this per placed widget. Changing it
    // would silently remove the widget from every existing user's home screen.
    let kind: String = "TimefoldWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TimefoldWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Latent")
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
