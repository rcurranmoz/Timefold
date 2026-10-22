import Foundation
import Photos
import UIKit
import ImageIO

/// One day as the widget will show it. Written ahead of time by the app, so
/// the widget can turn over at midnight on its own instead of showing
/// yesterday's photo under "memories from today" until the app is opened.
nonisolated struct WidgetDay: Codable, Sendable, Equatable {
    /// `yyyy-MM-dd`, the calendar day this entry is *for*.
    let day: String
    let count: Int
    /// How many distinct past years the day has photos from.
    let yearSpan: Int
    /// Strongest year first; the first tile is the hero.
    let tiles: [WidgetTile]
}

nonisolated struct WidgetTile: Codable, Sendable, Equatable {
    let year: Int
    /// File name inside the app group's widget folder.
    let file: String
}

/// Pure file I/O against the app-group container — safe from any thread,
/// and the widget already calls it off the main actor.
nonisolated final class SharedMemoriesManager: Sendable {
    static let shared = SharedMemoriesManager()

    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ryancurran.Timefold")
    }

    /// Widget photos live in their own folder so pruning can't touch anything
    /// else. Not Caches: the system may purge Caches while the widget still
    /// has days queued that point at these files.
    private var widgetFolder: URL? {
        guard let dir = containerURL?.appendingPathComponent("Widget", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var forecastURL: URL? {
        containerURL?.appendingPathComponent("widgetForecast.json")
    }

    // MARK: Forecast

    func saveForecast(_ days: [WidgetDay]) {
        guard let url = forecastURL, let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func readForecast() -> [WidgetDay] {
        guard let url = forecastURL,
              let data = try? Data(contentsOf: url),
              let days = try? JSONDecoder().decode([WidgetDay].self, from: data) else { return [] }
        return days
    }

    // MARK: Photos

    /// Render an asset into the widget folder. Returns whether it actually
    /// landed — callers must not reference a file that was never written.
    ///
    /// Network access is allowed: on an "Optimise iPhone Storage" library the
    /// best photo of the day is often only in iCloud, and the forecast is
    /// built in the background where a short wait costs nothing.
    @discardableResult
    func saveWidgetImage(from asset: PHAsset, named name: String, longEdge: CGFloat) -> Bool {
        guard let url = widgetFolder?.appendingPathComponent(name) else { return false }
        if FileManager.default.fileExists(atPath: url.path) { return true }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = true
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        var saved = false
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: longEdge, height: longEdge),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let data = image?.jpegData(compressionQuality: 0.85) else { return }
            saved = (try? data.write(to: url, options: .atomic)) != nil
        }
        return saved
    }

    /// Decode a widget photo no larger than it will be drawn. Widget
    /// extensions run under a hard memory ceiling, and a timeline holds
    /// several days of these at once.
    func readWidgetImage(named name: String, maxPixels: CGFloat) -> UIImage? {
        guard let url = widgetFolder?.appendingPathComponent(name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Remove widget photos no queued day refers to, plus the single-photo
    /// files from before the forecast existed.
    func pruneWidgetImages(keeping names: Set<String>) {
        if let folder = widgetFolder,
           let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for file in files where !names.contains(file) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
            }
        }
        for legacy in ["widgetPhoto.jpg", "todayCount.txt"] {
            if let url = containerURL?.appendingPathComponent(legacy) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
