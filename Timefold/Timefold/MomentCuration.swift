//
//  MomentCuration.swift
//  Latent
//
//  "The Pick" — collapse a day into moments and choose the best frame of each.
//
//  A day is not a list of files, it is a handful of moments that happen to have
//  been photographed several times each. Forty-four assets on July 2 is really
//  about fifteen things that happened. Everything user-facing that has to choose
//  *one* photo — the daily reveal's fan, the widget's background, a "best of"
//  grid — should be choosing between moments, not between files.
//
//  Entirely on-device. Nothing here touches the network, which is what lets the
//  permission screen keep saying "nothing leaves your device".
//

import Foundation
import Photos
import Vision
import UIKit

// MARK: - Per-asset scores

/// The part of an asset's score that is stable for the life of the asset, and
/// therefore worth keeping on disk.
///
/// Feature prints are deliberately *not* persisted. They are a few KB each and
/// are only ever compared against other assets from the same day, so they live
/// in memory for as long as that day is on screen and are recomputed after that.
/// Persisting them would turn a tiny cache into tens of megabytes for a large
/// library, to save work that is already cheap.
nonisolated struct AssetScore: Codable, Sendable {
    /// `ImageAestheticsScoresObservation.overallScore`. Measured on a real
    /// library this lands in roughly 0.2...0.75 for ordinary photographs, not
    /// the wider range the API's type suggests — so differences between frames
    /// of the same moment are small, and ties are common.
    let aesthetics: Float
    /// Apple's own "this is a screenshot / receipt / document" flag. This is the
    /// single highest-value signal in the whole pipeline: it removes the class of
    /// image that most pollutes a memory app, and it costs nothing extra.
    let isUtility: Bool
    /// `PHAsset.modificationDate` at scoring time. An edit in Photos.app changes
    /// this and invalidates the entry.
    let stamp: Double

    static func stamp(for asset: PHAsset) -> Double {
        asset.modificationDate?.timeIntervalSinceReferenceDate ?? 0
    }
}

/// One thing that happened, and the frames of it.
nonisolated struct Moment: Sendable, Identifiable {
    /// The frame to show when there is only room for one.
    let pick: PHAsset
    /// Every frame in this moment, newest first. Always contains `pick`.
    let members: [PHAsset]

    var id: String { pick.localIdentifier }
    var count: Int { members.count }
    var isStack: Bool { members.count > 1 }
    var date: Date? { pick.creationDate }
}

// MARK: - Tuning

/// Every threshold in one place, because all of them want to be validated
/// against a real library rather than guessed at. See `MomentCurationProbe`.
nonisolated enum CurationTuning {
    /// Long edge, in pixels, of the thumbnail handed to Vision. Both requests
    /// downscale internally; this only needs to be big enough to be honest.
    static let visionThumbnailPixels: CGFloat = 224

    /// Two frames further apart in time than this are always separate moments,
    /// however similar they look. Catches "same kitchen, eight months apart".
    ///
    /// Tightening this was tried and rejected: at 40s an eight-frame selfie
    /// burst split in two (a real regression) while the one known bad merge
    /// survived unchanged. The window is not the lever it looks like.
    static let maxSecondsWithinMoment: TimeInterval = 150

    /// Time window used when feature prints are unavailable and the grouper is
    /// flying blind. Deliberately far tighter than the Vision-backed window:
    /// without seeing the images, only near-simultaneous frames are safe to
    /// merge.
    static let maxSecondsWithoutVision: TimeInterval = 6

    /// Feature-print distance below which two frames are "the same picture".
    ///
    /// Vision does not document the scale of this number. Tuned on a real
    /// library (833 assets over 10 days) by sweeping 0.30...1.20 and then
    /// *looking at the merges*, which is the only check that matters:
    ///
    ///   - 0.70 reduced assets by 38% but visibly over-merged — a street, an
    ///     arch, a house, a tree and a lawn collapsed into one "moment",
    ///     discarding four real photographs.
    ///   - 0.45 reduces by ~30% and holds up by eye: bursts stay together,
    ///     genuinely different subjects stay apart.
    ///
    /// Hiding a memory is far worse than showing a duplicate, so this sits
    /// deliberately on the conservative side of what the numbers alone allow.
    static let maxFeaturePrintDistance: Double = 0.45

    /// How much being flagged `isUtility` costs a frame when picking a winner.
    /// Large enough that a screenshot never beats a real photograph.
    static let utilityPenalty: Float = 10
}

// MARK: - Curator

/// Scores assets and groups them into moments.
///
/// An `actor` on purpose: this target sets `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so a plain class here would quietly run Vision on the main
/// thread. The cache is actor state; the heavy work is `nonisolated`.
actor MomentCurator {
    static let shared = MomentCurator()

    private(set) var scores: [String: AssetScore] = [:]
    private var loadedFromDisk = false

    /// Feature prints for the day currently being looked at. Dropped whenever a
    /// different day is curated — see the note on `AssetScore`.
    private(set) var prints: [String: FeaturePrintObservation] = [:]
    private var printsDayKey: String = ""

    /// Assets already put through Vision this session, whether or not it worked.
    /// Without this, an environment where Vision is unavailable re-attempts
    /// every asset on every pass forever. Session-scoped on purpose: a fresh
    /// launch should try again.
    private var attempted: Set<String> = []

    /// False once a pass has produced no feature prints at all — Vision's ML
    /// requests are unavailable (they fail with "Failed to create espresso
    /// context" on the simulator). Grouping then falls back to burst identifiers
    /// and a tight time window, so the moment count is a *floor*, not an answer.
    /// Callers must not present it as a headline number when this is false.
    private(set) var visionAvailable = true

    /// Live threshold, seeded from `CurationTuning` and overridable so it can be
    /// swept against a real library instead of guessed at.
    private(set) var distanceThreshold: Double = CurationTuning.maxFeaturePrintDistance
    func setDistanceThreshold(_ value: Double) { distanceThreshold = value }

    private(set) var timeWindow: TimeInterval = CurationTuning.maxSecondsWithinMoment
    func setTimeWindow(_ value: TimeInterval) { timeWindow = value }

    // MARK: Entry point

    /// Curate one day's assets into moments, newest first.
    ///
    /// `assets` is expected in the order the rest of the app uses it:
    /// `creationDate` descending.
    func moments(for assets: [PHAsset], dayKey: String) async -> [Moment] {
        guard !assets.isEmpty else { return [] }
        loadScoresIfNeeded()

        if printsDayKey != dayKey {
            prints.removeAll(keepingCapacity: true)
            printsDayKey = dayKey
        }

        await ensureScored(assets)
        let grouped = group(assets)
        persistScores()
        return grouped
    }

    /// Up to `limit` frames for the daily reveal's fan: the best moment of each
    /// year, most recent year first.
    ///
    /// The reveal used to fan `assets.prefix(5)`, and assets sort by
    /// creationDate descending — so it always dealt five files from the most
    /// recent year, often five frames of the same thirty seconds. On one real
    /// day that meant opening the app with three photographs of a flat tyre.
    func revealFan(for assets: [PHAsset], dayKey: String, limit: Int = 5) async -> [PHAsset] {
        let moments = await moments(for: assets, dayKey: dayKey)
        guard !moments.isEmpty else { return Array(assets.prefix(limit)) }

        let calendar = Calendar.current
        var bestByYear: [Int: Moment] = [:]
        for moment in moments {
            guard let date = moment.date else { continue }
            let year = calendar.component(.year, from: date)
            if let held = bestByYear[year], rank(of: held.pick) >= rank(of: moment.pick) { continue }
            bestByYear[year] = moment
        }

        // Newest year first, matching the order the rest of the app reads in.
        var fan = bestByYear.keys.sorted(by: >).compactMap { bestByYear[$0]?.pick }

        // Short on years? Fill from the strongest moments not already in.
        if fan.count < limit {
            let taken = Set(fan.map(\.localIdentifier))
            let rest = moments.map(\.pick)
                .filter { !taken.contains($0.localIdentifier) }
                .sorted { rank(of: $0) > rank(of: $1) }
            fan.append(contentsOf: rest.prefix(limit - fan.count))
        }
        return Array(fan.prefix(limit))
    }

    /// The single best frame of a day — what the widget wants.
    func bestAsset(in assets: [PHAsset], dayKey: String) async -> PHAsset? {
        let moments = await moments(for: assets, dayKey: dayKey)
        return moments
            .map(\.pick)
            .max { rank(of: $0) < rank(of: $1) }
    }

    // MARK: Scoring

    private func ensureScored(_ assets: [PHAsset]) async {
        let needed = assets.filter { asset in
            if asset.mediaType == .video { return false }
            let id = asset.localIdentifier
            if let cached = scores[id], cached.stamp != AssetScore.stamp(for: asset) {
                return true   // edited since we scored it
            }
            if prints[id] != nil { return false }
            return !attempted.contains(id)
        }
        guard !needed.isEmpty else { return }

        // Bounded parallelism: four decodes in flight keeps the GPU and the
        // Neural Engine busy without letting four dozen full-size bitmaps
        // exist at once.
        let results = await withTaskGroup(
            of: (String, AssetScore?, FeaturePrintObservation?).self
        ) { group -> [(String, AssetScore?, FeaturePrintObservation?)] in
            var iterator = needed.makeIterator()
            var inFlight = 0
            var out: [(String, AssetScore?, FeaturePrintObservation?)] = []
            out.reserveCapacity(needed.count)

            func addNext() {
                guard let asset = iterator.next() else { return }
                let stamp = AssetScore.stamp(for: asset)
                let id = asset.localIdentifier
                group.addTask {
                    await Self.score(asset: asset, stamp: stamp, id: id)
                }
                inFlight += 1
            }

            for _ in 0..<4 { addNext() }
            while inFlight > 0, let result = await group.next() {
                inFlight -= 1
                out.append(result)
                addNext()
            }
            return out
        }

        var gotAnyPrint = false
        for (id, score, print) in results {
            attempted.insert(id)
            if let score { scores[id] = score }
            if let print { prints[id] = print; gotAnyPrint = true }
        }
        // One pass over a non-empty set that yields nothing means the ML
        // requests are unavailable, not that these particular photos are odd.
        if !results.isEmpty { visionAvailable = gotAnyPrint }
    }

    /// One thumbnail decode feeds both Vision requests — the decode is the
    /// expensive half, so running the two requests separately would double the
    /// cost of the whole pass for nothing.
    private nonisolated static func score(
        asset: PHAsset,
        stamp: Double,
        id: String
    ) async -> (String, AssetScore?, FeaturePrintObservation?) {
        guard let cgImage = await visionThumbnail(for: asset) else {
            return (id, nil, nil)
        }

        async let aestheticsTask = try? CalculateImageAestheticsScoresRequest()
            .perform(on: cgImage)
        async let printTask = try? GenerateImageFeaturePrintRequest()
            .perform(on: cgImage)

        let aesthetics = await aestheticsTask
        let print = await printTask

        let score = aesthetics.map {
            AssetScore(aesthetics: $0.overallScore, isUtility: $0.isUtility, stamp: stamp)
        }
        return (id, score, print)
    }

    private nonisolated static func visionThumbnail(for asset: PHAsset) async -> CGImage? {
        let options = PHImageRequestOptions()
        // `.highQualityFormat` fires the callback exactly once, which is what
        // makes it safe to bridge to a continuation. `.opportunistic` would fire
        // twice and resume the continuation twice — a crash, not a glitch.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let side = CurationTuning.visionThumbnailPixels
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
        return image?.cgImage
    }

    // MARK: Grouping

    /// Walk the day in order, extending the current moment while the next frame
    /// still looks and feels like the same thing.
    ///
    /// Assets arrive `creationDate` descending, so frames from different years
    /// are separated by enormous time gaps and fall apart on the time test alone
    /// — the visual test only ever has to arbitrate within a single afternoon.
    private func group(_ assets: [PHAsset]) -> [Moment] {
        var moments: [Moment] = []
        var current: [PHAsset] = []

        func close() {
            guard !current.isEmpty else { return }
            moments.append(Moment(pick: best(of: current), members: current))
            current = []
        }

        for asset in assets {
            guard let previous = current.last, let anchor = current.first else {
                current = [asset]
                continue
            }
            // Adjacency alone chains: A merges with B, B with C, and a moment
            // drifts away from where it started — a swing, a swing, and a slide
            // end up as one thing. Every frame must also still resemble the
            // frame the moment *opened* with.
            if belongTogether(previous, asset), resembles(anchor, asset) {
                current.append(asset)
            } else {
                close()
                current = [asset]
            }
        }
        close()
        return moments
    }

    private func belongTogether(_ a: PHAsset, _ b: PHAsset) -> Bool {
        // A video is its own moment. Scoring a poster frame for aesthetics says
        // nothing useful, and silently folding a clip into a photo stack would
        // hide it.
        guard a.mediaType == .image, b.mediaType == .image else { return false }

        // Photos already told us these are one burst. Trust it and skip the
        // work — this path needs no Vision at all.
        if let burst = a.burstIdentifier, burst == b.burstIdentifier { return true }

        guard let aDate = a.creationDate, let bDate = b.creationDate else { return false }
        let gap = abs(aDate.timeIntervalSince(bDate))

        // With feature prints, time is a cheap pre-filter and the images decide.
        if let aPrint = prints[a.localIdentifier],
           let bPrint = prints[b.localIdentifier],
           let distance = try? aPrint.distance(to: bPrint) {
            return gap <= timeWindow && distance < distanceThreshold
        }

        // No feature prints — Vision's ML requests are unavailable (notably on
        // the simulator, where they fail with "Failed to create espresso
        // context"), or this asset failed to decode. Fall back to a much
        // tighter time window: shots this close together are near-certainly the
        // same thing, and this at least collapses rapid-fire sequences that
        // Photos did not tag as a burst. Never guess beyond that.
        return gap <= CurationTuning.maxSecondsWithoutVision
    }

    /// Visual-only test against the frame a moment opened with. No time test:
    /// the gap to the anchor legitimately grows as a moment runs on, and the
    /// consecutive-pair check already bounds that.
    private func resembles(_ anchor: PHAsset, _ candidate: PHAsset) -> Bool {
        if let burst = anchor.burstIdentifier, burst == candidate.burstIdentifier { return true }
        guard let a = prints[anchor.localIdentifier],
              let b = prints[candidate.localIdentifier],
              let distance = try? a.distance(to: b) else {
            // No prints: the consecutive-pair check is already running its
            // tight no-Vision window, so don't veto on top of it.
            return true
        }
        return distance < distanceThreshold
    }

    // MARK: Picking

    private func best(of assets: [PHAsset]) -> PHAsset {
        assets.max { rank(of: $0) < rank(of: $1) } ?? assets[0]
    }

    /// Higher is better. Unscored assets (videos, failures) sit at neutral so
    /// they neither win nor lose against a photograph on a technicality.
    private func rank(of asset: PHAsset) -> Float {
        guard let score = scores[asset.localIdentifier] else { return 0 }
        return score.aesthetics - (score.isUtility ? CurationTuning.utilityPenalty : 0)
    }

    // MARK: Persistence

    private static let cacheURL: URL? = {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.ryancurran.Timefold")?
            .appendingPathComponent("assetScores.json")
    }()

    private func loadScoresIfNeeded() {
        guard !loadedFromDisk else { return }
        loadedFromDisk = true
        guard let url = Self.cacheURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: AssetScore].self, from: data)
        else { return }
        scores = decoded
    }

    private func persistScores() {
        guard let url = Self.cacheURL,
              let data = try? JSONEncoder().encode(scores) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Drop everything. Used by the probe and by a future "recompute" control.
    func reset() {
        scores = [:]
        prints = [:]
        printsDayKey = ""
        attempted = []
        visionAvailable = true
        loadedFromDisk = false
        if let url = Self.cacheURL { try? FileManager.default.removeItem(at: url) }
    }
}

// MARK: - Day keys

extension MomentCurator {
    /// Stable identity for "the day being shown", used to scope the in-memory
    /// feature-print cache.
    nonisolated static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
