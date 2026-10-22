//
//  WidgetForecast.swift
//  Latent
//
//  The widget can't read the photo library, so the app tells it about the
//  next few days in advance. Before this, the widget only learned anything
//  when the app was opened — so at midnight it redrew yesterday's photo
//  under "memories from today", and kept doing so until the next launch.
//

import Foundation
import Photos
import WidgetKit

enum WidgetForecaster {
    /// Today plus this many following days. Each costs a curation pass the
    /// first time (cached after), and each queued day holds a few photos in
    /// the widget's memory budget — three is a long weekend of not opening
    /// the app, and cheap.
    nonisolated static let daysAhead = 2

    /// Hero plus up to three other years for the medium and large widgets.
    nonisolated static let tilesPerDay = 4

    /// Rebuild the forecast if today's isn't current. Safe to call on every
    /// load of today; it returns immediately when nothing has changed.
    nonisolated static func refresh(todayCount: Int) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayKey = DayLink.dayFormatter.string(from: today)

        let existing = SharedMemoriesManager.shared.readForecast()
        if let first = existing.first, first.day == todayKey, first.count == todayCount,
           existing.count > daysAhead {
            return
        }

        var days: [WidgetDay] = []
        var files: Set<String> = []
        for offset in 0...daysAhead {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = DayLink.dayFormatter.string(from: date)
            let assets = MemoriesViewModel.fetchMemories(for: date)
            guard !assets.isEmpty else {
                days.append(WidgetDay(day: key, count: 0, yearSpan: 0, tiles: []))
                continue
            }

            let ranked = await MomentCurator.shared.rankedYears(
                for: assets, dayKey: MomentCurator.dayKey(for: date))
            var tiles: [WidgetTile] = []
            for (year, asset) in ranked {
                guard tiles.count < tilesPerDay else { break }
                // Keyed on the asset as well as the day, so a changed pick is
                // a new file and the widget never shows a stale one.
                let safeID = asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
                let name = "\(key)-\(year)-\(safeID).jpg"
                let edge: CGFloat = tiles.isEmpty ? 900 : 360
                if SharedMemoriesManager.shared.saveWidgetImage(from: asset, named: name, longEdge: edge) {
                    tiles.append(WidgetTile(year: year, file: name))
                    files.insert(name)
                }
            }
            days.append(WidgetDay(day: key, count: assets.count, yearSpan: ranked.count, tiles: tiles))
        }

        guard days != existing else { return }
        SharedMemoriesManager.shared.saveForecast(days)
        SharedMemoriesManager.shared.pruneWidgetImages(keeping: files)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
