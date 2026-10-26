import WidgetKit
import SwiftUI
import UIKit

// MARK: - Timeline

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), day: nil, hero: nil, others: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        completion(Self.entries(for: context.family).first ?? placeholder(in: context))
    }

    /// One entry per forecast day, each dated to its own midnight, so the
    /// widget turns the page by itself. Past the end of the forecast it falls
    /// back to an honest "open Latent" rather than a confident wrong number.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entries = Self.entries(for: context.family)
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func entries(for family: WidgetFamily) -> [SimpleEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let forecast = SharedMemoriesManager.shared.readForecast()

        var entries: [SimpleEntry] = []
        for day in forecast {
            guard let date = dayFormatter.date(from: day.day), date >= today else { continue }
            entries.append(entry(for: day, date: date == today ? Date() : date, family: family))
        }
        // The day after the forecast runs out: don't keep claiming the last
        // known day's photos are "today".
        let end = entries.last.map { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0.date))! }
            ?? Date()
        entries.append(SimpleEntry(date: end, day: nil, hero: nil, others: []))
        return entries
    }

    /// Read the shared container here — not from the view body. Decoded at
    /// the size it will be drawn: widget extensions have a hard memory
    /// ceiling and a timeline holds several days at once.
    private static func entry(for day: WidgetDay, date: Date, family: WidgetFamily) -> SimpleEntry {
        let store = SharedMemoriesManager.shared
        guard family.usesPhotoBackground else {
            return SimpleEntry(date: date, day: day, hero: nil, others: [])
        }
        let hero = day.tiles.first.flatMap { store.readWidgetImage(named: $0.file, maxPixels: family == .systemSmall ? 520 : 900) }
        let others: [YearPhoto] = family == .systemSmall ? [] : day.tiles.dropFirst().map {
            YearPhoto(year: $0.year, image: store.readWidgetImage(named: $0.file, maxPixels: 240))
        }
        return SimpleEntry(date: date, day: day, hero: hero, others: others)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
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

struct YearPhoto: Identifiable {
    let year: Int
    let image: UIImage?
    var id: Int { year }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    /// nil when the forecast has nothing for this date.
    let day: WidgetDay?
    let hero: UIImage?
    let others: [YearPhoto]

    var count: Int { day?.count ?? 0 }
    var heroYear: Int? { day?.tiles.first?.year }
    var thisYear: Int { Calendar.current.component(.year, from: date) }

    func yearsAgo(_ year: Int) -> Int { thisYear - year }

    /// "6 years ago" — the line that gives the photo its meaning.
    func agoText(_ year: Int) -> String {
        let n = yearsAgo(year)
        switch n {
        case ..<1: return "Earlier this year"
        case 1:    return "A year ago"
        default:   return "\(n) years ago"
        }
    }

    var memoriesText: String { count == 1 ? "1 MEMORY" : "\(count) MEMORIES" }

    /// Deep link into the app, optionally to one year's chapter.
    func link(year: Int?) -> URL {
        let dayKey = day?.day ?? Provider.dayFormatter.string(from: date)
        var s = "latent://day/\(dayKey)"
        if let year { s += "?year=\(year)" }
        return URL(string: s)!
    }
}

// MARK: - Look

/// The app's warm palette, restated for the widget target (the app's
/// `Theme` lives in a file the extension doesn't compile).
private enum WidgetTheme {
    static let cream = Color(red: 0.99, green: 0.96, blue: 0.90)
    static let mat   = Color(red: 1.00, green: 0.99, blue: 0.96)
    static let ink   = Color(red: 0.27, green: 0.17, blue: 0.19)
    static let inkSoft = Color(red: 0.48, green: 0.35, blue: 0.37)
    static let plum  = Color(red: 0.22, green: 0.14, blue: 0.27)

    static func sky(_ scheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = scheme == .dark
            ? [Color(red: 0.20, green: 0.13, blue: 0.26), Color(red: 0.36, green: 0.21, blue: 0.30)]
            : [Color(red: 1.00, green: 0.96, blue: 0.87), Color(red: 0.99, green: 0.84, blue: 0.78)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .serif) }

    /// Shadow that keeps white type legible on any photograph.
    static let legible = Color.black.opacity(0.45)
}

private struct Meta: View {
    let text: String
    var color: Color = .white.opacity(0.85)
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .kerning(1.4)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// A small photo with its year underneath, polaroid-ish.
private struct YearTile: View {
    let photo: YearPhoto
    let size: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Group {
                if let image = photo.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    WidgetTheme.cream.opacity(0.3)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(String(photo.year))
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .italic()
        }
    }
}

// MARK: - Views

struct TimefoldWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var scheme

    var body: some View {
        Group {
            if entry.day == nil {
                StaleView()
            } else if entry.count == 0 {
                QuietDayView(entry: entry)
            } else {
                switch family {
                case .systemSmall:          SmallWidgetView(entry: entry)
                case .systemMedium:         MediumWidgetView(entry: entry)
                case .systemLarge:          LargeWidgetView(entry: entry)
                case .accessoryCircular:    AccessoryCircularView(entry: entry)
                case .accessoryRectangular: AccessoryRectangularView(entry: entry)
                default:                    SmallWidgetView(entry: entry)
                }
            }
        }
        .widgetURL(entry.link(year: entry.heroYear))
        .containerBackground(for: .widget) {
            if family.usesPhotoBackground {
                if let hero = entry.hero, family != .systemLarge {
                    ZStack {
                        Image(uiImage: hero).resizable().scaledToFill()
                        // Darken toward where the type sits.
                        LinearGradient(colors: [.clear, .black.opacity(0.62)],
                                       startPoint: family == .systemMedium ? .trailing : .center,
                                       endPoint: family == .systemMedium ? .leading : .bottom)
                    }
                } else {
                    WidgetTheme.sky(scheme)
                }
            }
        }
    }
}

/// Full-bleed photo, and the one line that gives it meaning.
struct SmallWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LatentMark(monochrome: .white)
                .frame(height: 10)
                .shadow(color: WidgetTheme.legible, radius: 3)
            Spacer()
            if let year = entry.heroYear {
                Text(entry.agoText(year))
                    .font(WidgetTheme.serif(19))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .shadow(color: WidgetTheme.legible, radius: 4)
            }
            Meta(text: entry.memoriesText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The best photo behind the day, with two more years to jump to.
struct MediumWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                LatentMark(monochrome: .white)
                    .frame(height: 10)
                    .shadow(color: WidgetTheme.legible, radius: 3)
                Spacer()
                Text(entry.date, format: .dateTime.month(.wide).day())
                    .font(WidgetTheme.serif(22))
                    .foregroundStyle(.white)
                    .shadow(color: WidgetTheme.legible, radius: 4)
                if let year = entry.heroYear {
                    Text("\(entry.agoText(year)) · \(String(year))")
                        .font(.system(size: 12, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: WidgetTheme.legible, radius: 3)
                }
                Meta(text: spanText(entry))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            if !entry.others.isEmpty {
                VStack(spacing: 6) {
                    ForEach(entry.others.prefix(2)) { photo in
                        Link(destination: entry.link(year: photo.year)) {
                            YearTile(photo: photo, size: 50)
                                .foregroundStyle(.white)
                                .shadow(color: WidgetTheme.legible, radius: 3)
                        }
                    }
                }
            }
        }
    }
}

/// A page of the day: the best photo on top, a row of other years beneath.
struct LargeWidgetView: View {
    let entry: SimpleEntry
    @Environment(\.colorScheme) var scheme

    private var ink: Color { scheme == .dark ? WidgetTheme.cream : WidgetTheme.ink }
    private var inkSoft: Color { scheme == .dark ? WidgetTheme.cream.opacity(0.7) : WidgetTheme.inkSoft }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let hero = entry.hero {
                        Image(uiImage: hero).resizable().scaledToFill()
                    } else {
                        WidgetTheme.cream.opacity(0.4)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipped()
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.5)],
                                        startPoint: .center, endPoint: .bottom))

                if let year = entry.heroYear {
                    Text("\(entry.agoText(year)) · \(String(year))")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .italic()
                        .foregroundStyle(.white)
                        .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(alignment: .firstTextBaseline) {
                Text(entry.date, format: .dateTime.month(.wide).day())
                    .font(WidgetTheme.serif(24))
                    .foregroundStyle(ink)
                Spacer()
                LatentMark().frame(height: 12)
            }
            Meta(text: spanText(entry), color: inkSoft)

            Spacer(minLength: 0)

            if !entry.others.isEmpty {
                HStack(spacing: 10) {
                    ForEach(entry.others.prefix(3)) { photo in
                        Link(destination: entry.link(year: photo.year)) {
                            YearTile(photo: photo, size: 70)
                                .foregroundStyle(inkSoft)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private func spanText(_ entry: SimpleEntry) -> String {
    let span = entry.day?.yearSpan ?? 0
    return span > 1 ? "\(entry.memoriesText) · \(span) YEARS" : entry.memoriesText
}

/// A day with nothing behind it. Said warmly, not as an error.
private struct QuietDayView: View {
    let entry: SimpleEntry
    @Environment(\.colorScheme) var scheme
    @Environment(\.widgetFamily) var family

    var body: some View {
        let ink = scheme == .dark ? WidgetTheme.cream : WidgetTheme.ink
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                LatentMark(monochrome: .primary).frame(height: 12)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Latent").font(.caption2.weight(.semibold))
                Text("A quiet day").font(.headline)
                Text("make one worth keeping").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                LatentMark().frame(height: 11)
                Spacer()
                Text("A quiet day")
                    .font(WidgetTheme.serif(19))
                    .foregroundStyle(ink)
                Text("Today's photos become next year's memories.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The forecast has run out — the app hasn't been opened in a few days.
private struct StaleView: View {
    @Environment(\.colorScheme) var scheme
    @Environment(\.widgetFamily) var family

    var body: some View {
        let ink = scheme == .dark ? WidgetTheme.cream : WidgetTheme.ink
        if family.usesPhotoBackground {
            VStack(spacing: 8) {
                LatentMark().frame(height: 16)
                Text("Open Latent")
                    .font(WidgetTheme.serif(16))
                    .foregroundStyle(ink)
                Text("to see today's memories")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                LatentMark(monochrome: .primary).frame(height: 12)
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
            Text(entry.heroYear.map { "\(entry.agoText($0)) today" } ?? "On this day")
                .font(.headline.weight(.bold))
                .minimumScaleFactor(0.7)
            Text("\(entry.count) \(entry.count == 1 ? "memory" : "memories")")
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
        .description("The best photo from this day in past years.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
