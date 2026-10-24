//
//  LivePhoto.swift
//  Latent
//
//  Live Photos were shown as stills. In a memories app the three seconds of
//  motion and sound around the shutter are often the best part — the laugh
//  before the smile, the wave that the still frame cuts off.
//

import SwiftUI
import Photos
import PhotosUI
import AVFoundation

/// Plays a Live Photo on demand. Mounted only while playing: at rest the
/// pager's own still image is what's on screen, so zoom, pan and the share
/// sheet keep working exactly as they do for any photo.
struct LivePhotoPlayer: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let style: PHLivePhotoViewPlaybackStyle
    let onEnd: () -> Void

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.livePhoto = livePhoto
        view.delegate = context.coordinator
        // The hint is a silent shimmer; full playback has sound.
        view.isMuted = style == .hint
        // Our own long-press drives playback; the built-in one would fight
        // the pager's gestures.
        view.playbackGestureRecognizer.isEnabled = false
        view.startPlayback(with: style)
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        context.coordinator.onEnd = onEnd
    }

    func makeCoordinator() -> Coordinator { Coordinator(onEnd: onEnd) }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var onEnd: () -> Void
        init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }

        func livePhotoView(_ view: PHLivePhotoView, didEndPlaybackWith style: PHLivePhotoViewPlaybackStyle) {
            onEnd()
        }
    }
}

enum LivePhotoLoader {
    /// The paired video arrives with the photo. Network allowed: on an
    /// optimised library the motion half is often only in iCloud.
    static func load(_ asset: PHAsset, targetSize: CGSize) async -> PHLivePhoto? {
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestLivePhoto(
                for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
            ) { photo, info in
                // Can call back more than once; only the final, non-degraded
                // result is worth playing — and a continuation resumes once.
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: photo)
            }
        }
    }
}

extension PHAsset {
    var isLivePhoto: Bool { mediaSubtypes.contains(.photoLive) }
}

/// The small "LIVE" tag Photos uses, in the pager's white-on-photo voice.
struct LiveBadge: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPlaying ? "livephoto.play" : "livephoto")
                .font(.system(size: 12, weight: .semibold))
                .symbolEffect(.pulse, isActive: isPlaying)
            Text("LIVE")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .kerning(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.4)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}
