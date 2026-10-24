//
//  Chapters.swift
//  Latent
//
//  A day of memories is a stack of years. Each year is a chapter: a pinned
//  header saying when and how long ago, then that year's photos — led, when
//  there are enough of them to deserve it, by the year's best frame drawn
//  wide.
//

import SwiftUI
import Photos

struct Chapter: Identifiable {
    let year: Int
    /// Reading order: the lead first (if it is in this chapter), then the rest
    /// newest first.
    let items: [PHAsset]
    /// Drawn full width above the grid. Only when the year has enough photos
    /// that one of them standing out still leaves a grid beneath it — a hero
    /// over a single row of two looks like a layout bug, not an editorial
    /// choice.
    let hero: PHAsset?

    var id: Int { year }
    var rest: ArraySlice<PHAsset> { hero == nil ? items[...] : items.dropFirst() }

    static let heroMinimum = 4

    static func anchor(_ year: Int) -> String { "chapter-\(year)" }

    /// Split newest-first assets into years. Assets arrive sorted by
    /// creationDate descending, so each year is already contiguous.
    static func build(from assets: [PHAsset], leads: [Int: String]) -> [Chapter] {
        let calendar = Calendar.current
        var chapters: [Chapter] = []
        var year: Int?
        var run: [PHAsset] = []

        func close() {
            guard let year, !run.isEmpty else { return }
            var items = run
            if let lead = leads[year],
               let i = items.firstIndex(where: { $0.localIdentifier == lead }), i > 0 {
                items.insert(items.remove(at: i), at: 0)
            }
            let hero = items.count >= heroMinimum ? items.first : nil
            chapters.append(Chapter(year: year, items: items, hero: hero))
        }

        for asset in assets {
            let y = asset.creationDate.map { calendar.component(.year, from: $0) } ?? 0
            if y != year {
                close()
                year = y
                run = []
            }
            run.append(asset)
        }
        close()
        return chapters
    }
}

/// Years-ago phrasing shared by chapter headers, the reveal and notifications.
enum YearsAgo {
    /// Anniversaries that deserve to be said out loud.
    static let milestones: Set<Int> = [1, 5, 10, 15, 20, 25, 30, 40, 50]

    static func count(from year: Int, to now: Date = Date()) -> Int {
        Calendar.current.component(.year, from: now) - year
    }

    /// "6 years ago", "Ten years ago" — milestones spelled out, because
    /// "ten years" is a different sentence from "10 years".
    static func phrase(_ n: Int, capitalized: Bool = false) -> String {
        let text: String
        switch n {
        case ..<1: text = "earlier this year"
        case 1:    text = "a year ago"
        default:
            if milestones.contains(n), let word = spelled(n) {
                text = "\(word) years ago"
            } else {
                text = "\(n) years ago"
            }
        }
        return capitalized ? text.prefix(1).uppercased() + text.dropFirst() : text
    }

    static func spelled(_ n: Int) -> String? {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        return f.string(from: NSNumber(value: n))
    }
}

/// Pinned above each year. Uses adaptive colours: it sits on system material,
/// which follows system appearance, not on the app's own sky.
struct ChapterHeader: View {
    let year: Int
    let count: Int
    let noun: String

    private var ago: Int { YearsAgo.count(from: year) }
    private var isMilestone: Bool { YearsAgo.milestones.contains(ago) && ago >= 5 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(year))
                .font(.latentSerif(24))
                .foregroundStyle(.primary)
            Text(YearsAgo.phrase(ago))
                .font(.latentSerif(15, weight: .regular))
                .italic()
                .foregroundStyle(isMilestone ? AnyShapeStyle(Theme.pink) : AnyShapeStyle(.secondary))
            Spacer()
            Text(count == 1 ? "1 \(noun)" : "\(count) \(noun == "MEMORY" ? "MEMORIES" : noun + "S")")
                .font(.latentRounded(10))
                .kerning(1.4)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
