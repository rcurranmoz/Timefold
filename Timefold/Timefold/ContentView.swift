import SwiftUI
import Photos
import Combine
import UIKit
import UserNotifications
import WidgetKit
import AVKit

struct ContentView: View {
    @StateObject private var model = MemoriesViewModel()
    @StateObject private var notificationManager = NotificationManager()
    @State private var viewMode: ViewMode = .grid
    @State private var showingSettings = false
    @State private var showingDatePicker = false
    @State private var selectedDate = Date()
    
    enum ViewMode {
        case grid
        case fullscreen
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .needsPermission:
                    PermissionView {
                        model.requestPermission()
                    }

                case .loading:
                    ProgressView("Loading memories…")
                        .padding()

                case .empty:
                    ContentUnavailableView(
                        "No memories found",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("No photos found for today in past years.\nCheck back tomorrow!")
                    )

                case .loaded(let assets):
                    if viewMode == .grid {
                        MemoriesGridView(assets: assets, isGridViewMode: $viewMode)
                    } else {
                        MemoryPagerView(
                            assets: assets,
                            startAsset: assets.first ?? assets[0],
                            onDismiss: {
                                withAnimation {
                                    viewMode = .grid
                                }
                            }
                        )
                    }

                case .error(let message):
                    ContentUnavailableView(
                        "Something went wrong",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("Timefold")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        HStack(spacing: 3) {
                            Text(formatDateString(selectedDate))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            if !Calendar.current.isDateInToday(selectedDate) {
                                Button {
                                    selectedDate = Date()
                                    model.loadMemoriesFor(date: Date())
                                } label: {
                                    Text("• Today")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    .fixedSize()
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.state)
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    // Fixed frame container
                    HStack {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    // Fixed frame container with exact width
                    HStack(spacing: 12) {
                        Button {
                            showingDatePicker = true
                        } label: {
                            Image(systemName: "calendar")
                                .opacity(viewMode == .grid ? 1 : 0)
                        }
                        .disabled(viewMode != .grid)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = viewMode == .grid ? .fullscreen : .grid
                            }
                        } label: {
                            Image(systemName: viewMode == .grid ? "square.fill.on.square.fill" : "square.grid.3x3.fill")
                        }
                    }
                    .frame(width: 100, height: 44)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            model.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Reload when app comes to foreground (in case date changed)
            model.loadMemoriesFor(date: selectedDate)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // Reload when system time/date changes (like manual date change)
            selectedDate = Date()
            model.loadMemoriesFor(date: Date())
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(notificationManager: notificationManager)
        }
        .sheet(isPresented: $showingDatePicker) {
            DatePickerView(selectedDate: $selectedDate, onDateSelected: {
                model.loadMemoriesFor(date: selectedDate)
                showingDatePicker = false
            })
        }
    }
    
    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
}

private struct PermissionView: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue.gradient)
                    .symbolEffect(.pulse)
                
                VStack(spacing: 8) {
                    Text("Your Memories Await")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Timefold shows you photos from this day in past years.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    onRequest()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                VStack(spacing: 4) {
                    Label("100% Private", systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("No accounts • No ads • Nothing leaves your device")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}

private struct MemoriesGridView: View {
    let assets: [PHAsset]
    @Binding var isGridViewMode: ContentView.ViewMode
    
    private let spacing: CGFloat = 2
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    
    @State private var deletedAssets: Set<String> = []
    
    // Multi-select mode
    @State private var isSelecting = false
    @State private var selectedAssets: Set<String> = []
    @State private var showingDeleteConfirmation = false

    var body: some View {
        ZStack {
            gridContent
            
            // Selection mode toolbar at bottom
            if isSelecting {
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        Text("\(selectedAssets.count) Selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .toolbar {
            // Only show these toolbar items when in grid mode
            if isGridViewMode == .grid {
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                withAnimation {
                                    isSelecting = false
                                    selectedAssets.removeAll()
                                }
                            }
                            
                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Text("Delete")
                            }
                            .disabled(selectedAssets.isEmpty)
                        }
                    } else {
                        Button {
                            withAnimation {
                                isSelecting = true
                            }
                        } label: {
                            Image(systemName: "checkmark.circle")
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete \(selectedAssets.count) \(selectedAssets.count == 1 ? "item" : "items")?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedPhotos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private var gridContent: some View {
        GeometryReader { geo in
            let cell = (geo.size.width - spacing * 2) / 3
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        if !deletedAssets.contains(asset.localIdentifier) {
                            GridCellView(
                                assets: assets,
                                asset: asset,
                                cellSize: cell,
                                isSelecting: isSelecting,
                                isSelected: selectedAssets.contains(asset.localIdentifier),
                                onToggleSelection: {
                                    toggleSelection(for: asset)
                                },
                                onDelete: {
                                    deletePhoto(asset: asset)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 0)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .bottom)
        }
    }
    
    private func toggleSelection(for asset: PHAsset) {
        if selectedAssets.contains(asset.localIdentifier) {
            selectedAssets.remove(asset.localIdentifier)
        } else {
            selectedAssets.insert(asset.localIdentifier)
        }
    }
    
    private func deleteSelectedPhotos() {
        let assetsToDelete = assets.filter { selectedAssets.contains($0.localIdentifier) }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    withAnimation {
                        // Mark as deleted
                        for asset in assetsToDelete {
                            deletedAssets.insert(asset.localIdentifier)
                        }
                        // Clear selection and exit selection mode
                        selectedAssets.removeAll()
                        isSelecting = false
                    }
                } else if let error = error {
                    print("Error deleting photos: \(error.localizedDescription)")
                }
            }
        }
    }

    private func deletePhoto(asset: PHAsset) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    withAnimation {
                        deletedAssets.insert(asset.localIdentifier)
                    }
                }
            }
        }
    }
}

private struct GridCellView: View {
    let assets: [PHAsset]
    let asset: PHAsset
    let cellSize: CGFloat
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        ZStack {
            if isSelecting {
                // In selection mode, use a button for selection
                Button {
                    onToggleSelection()
                } label: {
                    cellContent
                }
                .buttonStyle(.plain)
            } else {
                // In normal mode, use NavigationLink
                NavigationLink {
                    MemoryPagerView(assets: assets, startAsset: asset)
                } label: {
                    cellContent
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive, action: onDelete) {
                        Label(asset.mediaType == .video ? "Delete Video" : "Delete Photo", systemImage: "trash")
                    }
                }
            }
            
            // Selection overlay
            if isSelecting {
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(isSelected ? Color.blue : Color.white.opacity(0.3))
                                .frame(width: 28, height: 28)
                            
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .shadow(color: .black.opacity(0.2), radius: 2)
                        .padding(8)
                    }
                    Spacer()
                }
            }
        }
    }
    
    private var cellContent: some View {
        ZStack {
            AssetThumbnailView(asset: asset)
                .frame(width: cellSize, height: cellSize)
                .clipped()
                .opacity(isSelecting && !isSelected ? 0.6 : 1.0)
            
            // Video play icon overlay
            if asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                        
                        // Video duration
                        Text(formatDuration(asset.duration))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                        
                        Spacer()
                    }
                    .padding(6)
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct AssetThumbnailView: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true

        let target = CGSize(width: 300, height: 300)
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFill,
            options: opts
        ) { img, _ in
            self.image = img
        }
    }
}

private struct MemoryPagerView: View {
    let assets: [PHAsset]
    let startAsset: PHAsset
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var selection: Int = 0
    @State private var showingShare = false
    @State private var isPreparingShare = false
    @State private var shareItem: ShareItem?
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var storyImages: [String: UIImage] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @GestureState private var dragState: CGFloat = 0
    
    enum ShareItem {
        case image(UIImage)
        case video(PHAsset)
    }
    
    private var currentImage: UIImage? {
        guard let asset = assets[safe: selection] else { return nil }
        return loadedImages[asset.localIdentifier]
    }
    
    private var currentStoryImage: UIImage? {
        guard let asset = assets[safe: selection] else { return nil }
        return storyImages[asset.localIdentifier]
    }
    
    private var currentAsset: PHAsset? {
        assets[safe: selection]
    }

    private var currentAssetIsVideo: Bool {
        assets[safe: selection]?.mediaType == .video
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    PagedPhotoView(
                        asset: asset,
                        onImageReady: { img in
                            loadedImages[asset.localIdentifier] = img
                        },
                        onStoryImageReady: { storyImg in
                            storyImages[asset.localIdentifier] = storyImg
                        },
                        dragOffset: dragOffset
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: currentAssetIsVideo ? .never : .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .offset(y: dragOffset)
            .opacity(opacity)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        // Only respond to primarily vertical downward drags
                        let verticalAmount = value.translation.height
                        let horizontalAmount = abs(value.translation.width)
                        
                        // If it's more horizontal than vertical, let TabView handle it
                        guard verticalAmount > horizontalAmount else { return }
                        guard verticalAmount > 0 else { return }
                        
                        dragOffset = verticalAmount
                        opacity = max(0.5, 1.0 - (verticalAmount / 500))
                    }
                    .onEnded { value in
                        let verticalAmount = value.translation.height
                        let horizontalAmount = abs(value.translation.width)
                        
                        // Only dismiss if it was a vertical drag
                        guard verticalAmount > horizontalAmount else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                                opacity = 1.0
                            }
                            return
                        }
                        
                        let shouldDismiss = verticalAmount > 120 || value.velocity.height > 800
                        if shouldDismiss {
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffset = 500
                                opacity = 0
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                if let onDismiss {
                                    onDismiss()
                                } else {
                                    dismiss()
                                }
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                                opacity = 1.0
                            }
                        }
                    }
            )
            
            // Year badge overlay
            VStack {
                if let date = assets[safe: selection]?.creationDate {
                    HStack {
                        Spacer()
                        Text(yearsAgoText(from: date))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.trailing)
                    }
                    .padding(.top, 60)
                }
                Spacer()
            }
            .opacity(dragOffset > 20 ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: dragOffset)
        }
        .navigationBarBackButtonHidden(false)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Empty - just to maintain spacing
                Text("")
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Only show grid button when navigated (not when toggled from main view)
                if onDismiss == nil {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "square.grid.3x3.fill")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    .opacity(dragOffset > 20 ? 0 : 1)
                }
                
                Button {
                    showingShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .disabled(currentImage == nil || isPreparingShare)
                .opacity(dragOffset > 20 ? 0 : 1)
                .overlay {
                    if isPreparingShare {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear {
            if let i = assets.firstIndex(where: { $0.localIdentifier == startAsset.localIdentifier }) {
                selection = i
            }
        }
        .sheet(isPresented: $showingShare) {
            if let shareItem {
                switch shareItem {
                case .image(let image):
                    ActivityView(activityItems: [image])
                case .video(let asset):
                    VideoActivityView(asset: asset)
                }
            }
        }
        .onChange(of: showingShare) { newValue in
            if newValue {
                // Prepare share content
                isPreparingShare = true
                
                Task {
                    if currentAssetIsVideo, let asset = currentAsset {
                        // For videos, just pass the asset
                        await MainActor.run {
                            shareItem = .video(asset)
                            isPreparingShare = false
                        }
                    } else {
                        // For photos, prepare the story image
                        if let storyImage = currentStoryImage {
                            await MainActor.run {
                                shareItem = .image(storyImage)
                                isPreparingShare = false
                            }
                        } else if let currentImage, let asset = currentAsset {
                            // Generate story image if not ready
                            let storyImage = await Task.detached(priority: .userInitiated) {
                                return createStoryImage(from: currentImage, asset: asset) ?? currentImage
                            }.value
                            
                            await MainActor.run {
                                shareItem = .image(storyImage)
                                isPreparingShare = false
                            }
                        } else {
                            await MainActor.run {
                                isPreparingShare = false
                                showingShare = false
                            }
                        }
                    }
                }
            } else {
                // Clean up when sheet is dismissed
                shareItem = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Dismiss share sheet when returning from Instagram
            if showingShare {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingShare = false
                }
            }
        }
    }
    
    private func createStoryImage(from image: UIImage, asset: PHAsset) -> UIImage? {
        // Create a canvas sized for Instagram stories (9:16 aspect ratio)
        // Using smaller size for better compatibility
        let storySize = CGSize(width: 1080, height: 1920)  // Instagram's preferred size
        
        let renderer = UIGraphicsImageRenderer(size: storySize, format: UIGraphicsImageRendererFormat.default())
        
        let storyImage = renderer.image { context in
            let ctx = context.cgContext
            
            // Background gradient
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0).cgColor,
                UIColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0).cgColor
            ] as CFArray
            
            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: colors,
                locations: [0.0, 1.0]
            ) else { return }
            
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: storySize.width, y: storySize.height),
                options: []
            )
            
            // Calculate photo placement (centered, with padding)
            let maxPhotoWidth = storySize.width - 180
            let maxPhotoHeight = storySize.height - 600
            
            let imageAspect = image.size.width / image.size.height
            let photoRect: CGRect
            
            if imageAspect > maxPhotoWidth / maxPhotoHeight {
                // Width constrained
                let width = maxPhotoWidth
                let height = width / imageAspect
                photoRect = CGRect(
                    x: (storySize.width - width) / 2,
                    y: 300,
                    width: width,
                    height: height
                )
            } else {
                // Height constrained
                let height = maxPhotoHeight
                let width = height * imageAspect
                photoRect = CGRect(
                    x: (storySize.width - width) / 2,
                    y: 300,
                    width: width,
                    height: height
                )
            }
            
            // LOGO BADGE - In background above photo, bigger and subtle
            let logoY: CGFloat = 120  // Positioned in gradient area above photo
            let badgeCornerRadius: CGFloat = 32
            let badgeInternalPadding: CGFloat = 32
            
            // Logo dimensions - BIGGER (back to full size)
            let clockRadius: CGFloat = 42
            let dividerSpacing: CGFloat = 32
            let dividerWidth: CGFloat = 4
            
            // Calculate text size first
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 58, weight: .black),
                .foregroundColor: UIColor.white,
                .kern: 10
            ]
            let text = "TIMEFOLD" as NSString
            let textSize = text.size(withAttributes: textAttrs)
            
            // Calculate badge dimensions
            let badgeContentWidth = clockRadius * 2 + dividerSpacing + dividerWidth + dividerSpacing + textSize.width
            let badgeContentHeight = max(clockRadius * 2, textSize.height)
            let badgeWidth = badgeContentWidth + (badgeInternalPadding * 2)
            let badgeHeight = badgeContentHeight + (badgeInternalPadding * 2)
            
            // Position badge centered horizontally, above photo in gradient background
            let badgeX = (storySize.width - badgeWidth) / 2
            let badgeY = logoY
            let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
            
            // Draw rounded rectangle background with VERY SUBTLE shadow - blend into background
            ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 10, color: UIColor.black.withAlphaComponent(0.15).cgColor)
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeCornerRadius)
            UIColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 0.35).setFill()  // Very subtle 35% opacity
            badgePath.fill()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            
            // Calculate positions inside badge
            let clockCenterX = badgeX + badgeInternalPadding + clockRadius
            let clockCenterY = badgeY + badgeHeight / 2
            
            // Clock circle - WHITE with reduced opacity
            let clockPath = UIBezierPath(arcCenter: CGPoint(x: clockCenterX, y: clockCenterY),
                                          radius: clockRadius,
                                          startAngle: 0,
                                          endAngle: .pi * 2,
                                          clockwise: true)
            UIColor.white.withAlphaComponent(0.65).setStroke()  // 65% opacity for subtlety
            clockPath.lineWidth = 5
            clockPath.stroke()
            
            // Hour hand (pointing up) - WHITE with reduced opacity
            let hourPath = UIBezierPath()
            hourPath.move(to: CGPoint(x: clockCenterX, y: clockCenterY))
            hourPath.addLine(to: CGPoint(x: clockCenterX, y: clockCenterY - clockRadius * 0.6))
            hourPath.lineWidth = 5
            hourPath.lineCapStyle = .round
            UIColor.white.withAlphaComponent(0.65).setStroke()
            hourPath.stroke()
            
            // Minute hand (pointing right-ish) - WHITE with reduced opacity
            let minutePath = UIBezierPath()
            minutePath.move(to: CGPoint(x: clockCenterX, y: clockCenterY))
            minutePath.addLine(to: CGPoint(x: clockCenterX + clockRadius * 0.5, y: clockCenterY + clockRadius * 0.2))
            minutePath.lineWidth = 4.5
            minutePath.lineCapStyle = .round
            UIColor.white.withAlphaComponent(0.65).setStroke()
            minutePath.stroke()
            
            // Center dot - WHITE with reduced opacity
            let dotPath = UIBezierPath(arcCenter: CGPoint(x: clockCenterX, y: clockCenterY),
                                        radius: 5.5,
                                        startAngle: 0,
                                        endAngle: .pi * 2,
                                        clockwise: true)
            UIColor.white.withAlphaComponent(0.65).setFill()
            dotPath.fill()
            
            // Vertical divider line - WHITE with reduced opacity
            let dividerX = clockCenterX + clockRadius + dividerSpacing
            let dividerHeight = badgeContentHeight * 0.6
            let dividerPath = UIBezierPath()
            dividerPath.move(to: CGPoint(x: dividerX, y: clockCenterY - dividerHeight / 2))
            dividerPath.addLine(to: CGPoint(x: dividerX, y: clockCenterY + dividerHeight / 2))
            dividerPath.lineWidth = dividerWidth
            UIColor.white.withAlphaComponent(0.65).setStroke()
            dividerPath.stroke()
            
            // TIMEFOLD text - WHITE with reduced opacity
            let textX = dividerX + dividerSpacing
            let textY = clockCenterY - textSize.height / 2
            let subtleTextAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 58, weight: .black),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65),  // 65% opacity
                .kern: 10
            ]
            (text as NSString).draw(at: CGPoint(x: textX, y: textY), withAttributes: subtleTextAttrs)
            
            // Draw white rounded border around photo
            let borderRect = photoRect.insetBy(dx: -30, dy: -30)
            let borderPath = UIBezierPath(roundedRect: borderRect, cornerRadius: 24)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.setShadow(offset: CGSize(width: 0, height: 15), blur: 45, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            borderPath.fill()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            
            // Draw the photo with rounded corners
            ctx.saveGState()
            let photoPath = UIBezierPath(roundedRect: photoRect, cornerRadius: 18)
            photoPath.addClip()
            image.draw(in: photoRect)
            ctx.restoreGState()
            
            // Text overlay at bottom
            let dateText = formattedDateForStory(asset.creationDate)
            let yearsText = yearsAgoForStory(asset.creationDate)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            
            // Date text
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let dateString = dateText as NSString
            let dateSize = dateString.size(withAttributes: dateAttrs)
            ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            dateString.draw(
                at: CGPoint(x: (storySize.width - dateSize.width) / 2, y: photoRect.maxY + 75),
                withAttributes: dateAttrs
            )
            
            // Years ago text
            let yearsAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 54, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            let yearsString = yearsText as NSString
            let yearsSize = yearsString.size(withAttributes: yearsAttrs)
            yearsString.draw(
                at: CGPoint(x: (storySize.width - yearsSize.width) / 2, y: photoRect.maxY + 165),
                withAttributes: yearsAttrs
            )
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
        
        return storyImage
    }
    
    private func formattedDateForStory(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func yearsAgoForStory(_ date: Date?) -> String {
        guard let date else { return "" }
        
        // Calculate actual years elapsed
        let calendar = Calendar.current
        let now = Date()
        
        let dateYear = calendar.component(.year, from: date)
        let nowYear = calendar.component(.year, from: now)
        
        let dateMonthDay = calendar.dateComponents([.month, .day], from: date)
        let nowMonthDay = calendar.dateComponents([.month, .day], from: now)
        
        var yearsAgo = nowYear - dateYear
        
        if let dateMonth = dateMonthDay.month, let dateDay = dateMonthDay.day,
           let nowMonth = nowMonthDay.month, let nowDay = nowMonthDay.day {
            if nowMonth < dateMonth || (nowMonth == dateMonth && nowDay < dateDay) {
                yearsAgo -= 1
            }
        }
        
        if yearsAgo <= 0 {
            return "Today"
        } else if yearsAgo == 1 {
            return "1 year ago today"
        } else {
            return "\(yearsAgo) years ago today"
        }
    }

    private func yearsAgoText(from date: Date?) -> String {
        guard let date else { return "" }
        
        // Calculate actual years elapsed, not just calendar year difference
        let calendar = Calendar.current
        let now = Date()
        
        // Get the year components
        let dateYear = calendar.component(.year, from: date)
        let nowYear = calendar.component(.year, from: now)
        
        // Calculate if we've passed the anniversary this year
        let dateMonthDay = calendar.dateComponents([.month, .day], from: date)
        let nowMonthDay = calendar.dateComponents([.month, .day], from: now)
        
        var yearsAgo = nowYear - dateYear
        
        // If we haven't reached the anniversary yet this year, subtract 1
        if let dateMonth = dateMonthDay.month, let dateDay = dateMonthDay.day,
           let nowMonth = nowMonthDay.month, let nowDay = nowMonthDay.day {
            if nowMonth < dateMonth || (nowMonth == dateMonth && nowDay < dateDay) {
                yearsAgo -= 1
            }
        }
        
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        let dateStr = df.string(from: date)
        
        if yearsAgo <= 0 {
            return dateStr
        } else if yearsAgo == 1 {
            return "\(dateStr) • 1 year ago"
        } else {
            return "\(dateStr) • \(yearsAgo) years ago"
        }
    }
    
    private func shareCaption(from date: Date?) -> String {
        guard let date else { return "A memory from Timefold" }
        let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
        if years <= 0 {
            return "Today"
        } else if years == 1 {
            return "1 year ago today"
        } else {
            return "\(years) years ago today"
        }
    }
}

private struct PagedPhotoView: View {
    let asset: PHAsset
    let onImageReady: (UIImage?) -> Void
    let onStoryImageReady: (UIImage?) -> Void
    let dragOffset: CGFloat
    
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if asset.mediaType == .video {
                    // VIDEO VIEW
                    if let player {
                        VideoPlayer(player: player)
                            .onAppear {
                                // Load thumbnail for sharing
                                onImageReady(image)
                            }
                    } else if let image {
                        // Show thumbnail while video loads
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                        
                        // Big play button
                        Button {
                            loadAndPlayVideo()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.5), radius: 10)
                        }
                    } else {
                        ProgressView("Loading…")
                            .foregroundStyle(.white)
                    }
                } else {
                    // PHOTO VIEW (existing code)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        // Don't allow zoom while dismissing
                                        guard dragOffset == 0 else { return }
                                        scale = lastScale * value.magnification
                                    }
                                    .onEnded { _ in
                                        withAnimation(.spring(response: 0.3)) {
                                            if scale < 1.0 {
                                                scale = 1.0
                                            } else if scale > 4.0 {
                                                scale = 4.0
                                            }
                                            lastScale = scale
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                guard dragOffset == 0 else { return }
                                withAnimation(.spring(response: 0.3)) {
                                    if scale > 1.0 {
                                        scale = 1.0
                                        lastScale = 1.0
                                    } else {
                                        scale = 2.0
                                        lastScale = 2.0
                                    }
                                }
                            }
                            .onChange(of: dragOffset) {
                                // Reset zoom when starting to dismiss
                                if dragOffset > 0 && scale != 1.0 {
                                    withAnimation(.spring(response: 0.2)) {
                                        scale = 1.0
                                        lastScale = 1.0
                                    }
                                }
                            }
                    } else {
                        ProgressView("Loading…")
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color.black)
        }
        .task {
            await loadFull()
        }
        .onDisappear {
            // Stop video when leaving
            player?.pause()
            player = nil
        }
    }
    
    private func loadAndPlayVideo() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
            DispatchQueue.main.async {
                if let playerItem {
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.play()
                    self.isPlaying = true
                }
            }
        }
    }

    private func loadFull() async {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .none
        opts.isNetworkAccessAllowed = true

        let target = CGSize(width: 2500, height: 2500)
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: opts
        ) { img, _ in
            self.image = img
            // Notify parent immediately when image loads
            if let img {
                self.onImageReady(img)
                // Generate story image in background
                Task.detached(priority: .utility) {
                    let storyImage = await self.createStoryImageAsync(from: img, asset: self.asset)
                    await MainActor.run {
                        self.onStoryImageReady(storyImage)
                    }
                }
            }
        }
    }
    
    private func createStoryImageAsync(from image: UIImage, asset: PHAsset) async -> UIImage? {
        return await Task.detached(priority: .utility) {
            let storySize = CGSize(width: 720, height: 1280)
            let renderer = UIGraphicsImageRenderer(size: storySize)
            
            return renderer.image { context in
                let ctx = context.cgContext
                
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let colors = [
                    UIColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0).cgColor,
                    UIColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0).cgColor
                ] as CFArray
                
                guard let gradient = CGGradient(
                    colorsSpace: colorSpace,
                    colors: colors,
                    locations: [0.0, 1.0]
                ) else { return }
                
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: storySize.width, y: storySize.height),
                    options: []
                )
                
                let maxPhotoWidth = storySize.width - 120
                let maxPhotoHeight = storySize.height - 400
                
                let imageAspect = image.size.width / image.size.height
                let photoRect: CGRect
                
                if imageAspect > maxPhotoWidth / maxPhotoHeight {
                    let width = maxPhotoWidth
                    let height = width / imageAspect
                    photoRect = CGRect(
                        x: (storySize.width - width) / 2,
                        y: 200,
                        width: width,
                        height: height
                    )
                } else {
                    let height = maxPhotoHeight
                    let width = height * imageAspect
                    photoRect = CGRect(
                        x: (storySize.width - width) / 2,
                        y: 200,
                        width: width,
                        height: height
                    )
                }
                
                let borderRect = photoRect.insetBy(dx: -20, dy: -20)
                let borderPath = UIBezierPath(roundedRect: borderRect, cornerRadius: 16)
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: UIColor.black.withAlphaComponent(0.3).cgColor)
                borderPath.fill()
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
                
                // Draw the photo with rounded corners
                ctx.saveGState()
                let photoPath = UIBezierPath(roundedRect: photoRect, cornerRadius: 12)
                photoPath.addClip()
                image.draw(in: photoRect)
                ctx.restoreGState()
                
                // LOGO BADGE - In background above photo, bigger and subtle (scaled for 720px)
                let logoY: CGFloat = 80  // Positioned in gradient area above photo
                let badgeCornerRadius: CGFloat = 21
                let badgeInternalPadding: CGFloat = 21
                
                // Logo dimensions - BIGGER for 720px canvas
                let clockRadius: CGFloat = 28
                let dividerSpacing: CGFloat = 21
                let dividerWidth: CGFloat = 2.7
                
                // Calculate text size first
                let textAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 39, weight: .black),  // Scaled proportionally
                    .foregroundColor: UIColor.white,
                    .kern: 6.7
                ]
                let text = "TIMEFOLD" as NSString
                let textSize = text.size(withAttributes: textAttrs)
                
                // Calculate badge dimensions
                let badgeContentWidth = clockRadius * 2 + dividerSpacing + dividerWidth + dividerSpacing + textSize.width
                let badgeContentHeight = max(clockRadius * 2, textSize.height)
                let badgeWidth = badgeContentWidth + (badgeInternalPadding * 2)
                let badgeHeight = badgeContentHeight + (badgeInternalPadding * 2)
                
                // Position badge centered horizontally, above photo in gradient background
                let badgeX = (storySize.width - badgeWidth) / 2
                let badgeY = logoY
                let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
                
                // Draw rounded rectangle background with VERY SUBTLE shadow - blend into background
                ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 7, color: UIColor.black.withAlphaComponent(0.15).cgColor)
                let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeCornerRadius)
                UIColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 0.35).setFill()  // Very subtle 35% opacity
                badgePath.fill()
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
                
                // Calculate positions inside badge
                let clockCenterX = badgeX + badgeInternalPadding + clockRadius
                let clockCenterY = badgeY + badgeHeight / 2
                
                // Clock circle - WHITE with reduced opacity
                let clockPath = UIBezierPath(arcCenter: CGPoint(x: clockCenterX, y: clockCenterY),
                                              radius: clockRadius,
                                              startAngle: 0,
                                              endAngle: .pi * 2,
                                              clockwise: true)
                UIColor.white.withAlphaComponent(0.65).setStroke()  // 65% opacity for subtlety
                clockPath.lineWidth = 3.3
                clockPath.stroke()
                
                // Hour hand (pointing up) - WHITE with reduced opacity
                let hourPath = UIBezierPath()
                hourPath.move(to: CGPoint(x: clockCenterX, y: clockCenterY))
                hourPath.addLine(to: CGPoint(x: clockCenterX, y: clockCenterY - clockRadius * 0.6))
                hourPath.lineWidth = 3.3
                hourPath.lineCapStyle = .round
                UIColor.white.withAlphaComponent(0.65).setStroke()
                hourPath.stroke()
                
                // Minute hand (pointing right-ish) - WHITE with reduced opacity
                let minutePath = UIBezierPath()
                minutePath.move(to: CGPoint(x: clockCenterX, y: clockCenterY))
                minutePath.addLine(to: CGPoint(x: clockCenterX + clockRadius * 0.5, y: clockCenterY + clockRadius * 0.2))
                minutePath.lineWidth = 3
                minutePath.lineCapStyle = .round
                UIColor.white.withAlphaComponent(0.65).setStroke()
                minutePath.stroke()
                
                // Center dot - WHITE with reduced opacity
                let dotPath = UIBezierPath(arcCenter: CGPoint(x: clockCenterX, y: clockCenterY),
                                            radius: 3.7,
                                            startAngle: 0,
                                            endAngle: .pi * 2,
                                            clockwise: true)
                UIColor.white.withAlphaComponent(0.65).setFill()
                dotPath.fill()
                
                // Vertical divider line - WHITE with reduced opacity
                let dividerX = clockCenterX + clockRadius + dividerSpacing
                let dividerHeight = badgeContentHeight * 0.6
                let dividerPath = UIBezierPath()
                dividerPath.move(to: CGPoint(x: dividerX, y: clockCenterY - dividerHeight / 2))
                dividerPath.addLine(to: CGPoint(x: dividerX, y: clockCenterY + dividerHeight / 2))
                dividerPath.lineWidth = dividerWidth
                UIColor.white.withAlphaComponent(0.65).setStroke()
                dividerPath.stroke()
                
                // TIMEFOLD text - WHITE with reduced opacity
                let textX = dividerX + dividerSpacing
                let textY = clockCenterY - textSize.height / 2
                let subtleTextAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 39, weight: .black),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.65),  // 65% opacity
                    .kern: 6.7
                ]
                (text as NSString).draw(at: CGPoint(x: textX, y: textY), withAttributes: subtleTextAttrs)
                
                let dateText = self.formattedDateForStory(asset.creationDate)
                let yearsText = self.yearsAgoForStory(asset.creationDate)
                
                // Date text - centered and clean
                let dateAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let dateString = dateText as NSString
                let dateSize = dateString.size(withAttributes: dateAttrs)
                ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: UIColor.black.withAlphaComponent(0.3).cgColor)
                dateString.draw(
                    at: CGPoint(x: (storySize.width - dateSize.width) / 2, y: photoRect.maxY + 50),
                    withAttributes: dateAttrs
                )
                
                // Years ago text
                let yearsAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 36, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9)
                ]
                let yearsString = yearsText as NSString
                let yearsSize = yearsString.size(withAttributes: yearsAttrs)
                yearsString.draw(
                    at: CGPoint(x: (storySize.width - yearsSize.width) / 2, y: photoRect.maxY + 110),
                    withAttributes: yearsAttrs
                )
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
            }
        }.value
    }
    
    private func formattedDateForStory(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func yearsAgoForStory(_ date: Date?) -> String {
        guard let date else { return "" }
        
        // Calculate actual years elapsed
        let calendar = Calendar.current
        let now = Date()
        
        let dateYear = calendar.component(.year, from: date)
        let nowYear = calendar.component(.year, from: now)
        
        let dateMonthDay = calendar.dateComponents([.month, .day], from: date)
        let nowMonthDay = calendar.dateComponents([.month, .day], from: now)
        
        var yearsAgo = nowYear - dateYear
        
        if let dateMonth = dateMonthDay.month, let dateDay = dateMonthDay.day,
           let nowMonth = nowMonthDay.month, let nowDay = nowMonthDay.day {
            if nowMonth < dateMonth || (nowMonth == dateMonth && nowDay < dateDay) {
                yearsAgo -= 1
            }
        }
        
        if yearsAgo <= 0 {
            return "Today"
        } else if yearsAgo == 1 {
            return "1 year ago today"
        } else {
            return "\(yearsAgo) years ago today"
        }
    }
}

final class MemoriesViewModel: ObservableObject {
    enum State: Equatable {
        case needsPermission
        case loading
        case empty
        case loaded([PHAsset])
        case error(String)
        
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.needsPermission, .needsPermission),
                 (.loading, .loading),
                 (.empty, .empty):
                return true
            case (.loaded(let a), .loaded(let b)):
                return a.map(\.localIdentifier) == b.map(\.localIdentifier)
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var state: State = .loading

    func start() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        handle(status)
    }

    func requestPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.handle(status)
            }
        }
    }

    func reload() {
        guard state != .loading else { return }
        start()
    }

    private func handle(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized, .limited:
            loadOnThisDay()
        case .notDetermined:
            state = .needsPermission
        case .denied, .restricted:
            state = .error("Photo access is denied. Enable it in Settings → Privacy & Security → Photos.")
        @unknown default:
            state = .error("Unknown authorization status.")
        }
    }

    private func loadOnThisDay() {
        loadMemoriesFor(date: Date())
    }
    
    func loadMemoriesFor(date: Date) {
        state = .loading

        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let selectedYear = calendar.component(.year, from: date)

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)

        let results = PHAsset.fetchAssets(with: fetchOptions)

        var assets: [PHAsset] = []
        
        // Iterate in order to preserve the sort
        for i in 0..<results.count {
            let asset = results.object(at: i)
            guard let assetDate = asset.creationDate else { continue }
            let aDay = calendar.component(.day, from: assetDate)
            let aMonth = calendar.component(.month, from: assetDate)
            let aYear = calendar.component(.year, from: assetDate)

            // Skip photos from the selected year and future years
            guard aYear < selectedYear else { continue }

            if aDay == day && aMonth == month {
                assets.append(asset)
            }
        }

        DispatchQueue.main.async {
            self.state = assets.isEmpty ? .empty : .loaded(assets)
            
            // Save for widget
            if !assets.isEmpty {
                SharedMemoriesManager.shared.saveMemoryCount(assets.count)
                if let randomAsset = assets.randomElement() {
                    SharedMemoriesManager.shared.saveWidgetThumbnail(from: randomAsset)
                }
                
                // Tell widget to reload
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    let excludedActivityTypes: [UIActivity.ActivityType]? = nil
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            // Always dismiss the sheet, regardless of outcome
            DispatchQueue.main.async {
                presentationMode.wrappedValue.dismiss()
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct VideoActivityView: UIViewControllerRepresentable {
    let asset: PHAsset
    @Environment(\.presentationMode) private var presentationMode
    @State private var videoURL: URL?
    
    func makeUIViewController(context: Context) -> UIViewController {
        let container = UIViewController()
        
        // Request the video file
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in
            guard let urlAsset = avAsset as? AVURLAsset else { return }
            
            DispatchQueue.main.async {
                // Create activity view controller with the video URL
                let activityVC = UIActivityViewController(
                    activityItems: [urlAsset.url],
                    applicationActivities: nil
                )
                
                activityVC.completionWithItemsHandler = { activityType, completed, returnedItems, error in
                    DispatchQueue.main.async {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                container.present(activityVC, animated: true)
            }
        }
        
        return container
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - Scroll Tracking
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Notification Manager
class NotificationManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "notificationsEnabled")
            if isEnabled {
                requestPermission()
            } else {
                cancelNotifications()
            }
        }
    }
    
    @Published var notificationTime: Date {
        didSet {
            UserDefaults.standard.set(notificationTime, forKey: "notificationTime")
            if isEnabled {
                scheduleNotificationCheck()
            }
        }
    }
    
    @Published var minimumPhotos: Int {
        didSet {
            UserDefaults.standard.set(minimumPhotos, forKey: "minimumPhotos")
            if isEnabled {
                scheduleNotificationCheck()
            }
        }
    }
    
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        
        if let savedTime = UserDefaults.standard.object(forKey: "notificationTime") as? Date {
            self.notificationTime = savedTime
        } else {
            // Default to 9:00 AM
            var components = DateComponents()
            components.hour = 9
            components.minute = 0
            self.notificationTime = Calendar.current.date(from: components) ?? Date()
        }
        
        let savedMinimum = UserDefaults.standard.integer(forKey: "minimumPhotos")
        self.minimumPhotos = savedMinimum > 0 ? savedMinimum : 3
        
        if isEnabled {
            scheduleNotificationCheck()
        }
    }
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    self.scheduleNotificationCheck()
                } else {
                    self.isEnabled = false
                }
            }
        }
    }
    
    func scheduleNotificationCheck() {
        cancelNotifications()
        
        // Schedule a daily notification at the user's chosen time
        let components = Calendar.current.dateComponents([.hour, .minute], from: notificationTime)
        
        var dateComponents = DateComponents()
        dateComponents.hour = components.hour
        dateComponents.minute = components.minute
        
        // This will fire daily at the chosen time
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        // Elegant notification variations
        let notifications = [
            ("Your memories are ready", "Photos from this day in past years"),
            ("Time to look back", "See what you were up to today"),
            ("Memories from this day", "Tap to revisit the past"),
            ("Your past awaits", "Photos from years ago are waiting"),
            ("Ready to revisit today?", "See how this day looked before"),
            ("Take a moment to look back", "Your photos from this day"),
            ("What were you doing on this day?", "Find out in your memories"),
            ("See what you were up to", "Photos from this day over the years")
        ]
        
        let notification = notifications.randomElement() ?? notifications[0]
        
        let content = UNMutableNotificationContent()
        content.title = notification.0
        content.body = notification.1
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "dailyMemoriesCheck",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    func cancelNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["dailyMemoriesCheck"]
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["dailyMemoriesCheck"]
        )
    }
    
    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: Date())
    }
}

// MARK: - Date Picker View
struct DatePickerView: View {
    @Binding var selectedDate: Date
    let onDateSelected: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Jump to a date")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top, 32)
                
                Text("See photos from this day in past years")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Spacer()
                
                Button {
                    onDateSelected()
                } label: {
                    Text("Show Memories")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily Reminder", isOn: $notificationManager.isEnabled)
                    
                    if notificationManager.isEnabled {
                        DatePicker(
                            "Time",
                            selection: $notificationManager.notificationTime,
                            displayedComponents: .hourAndMinute
                        )
                        
                        Picker("Minimum Photos", selection: $notificationManager.minimumPhotos) {
                            Text("3 photos").tag(3)
                            Text("5 photos").tag(5)
                            Text("10 photos").tag(10)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get a notification each morning if you have memories to see today.")
                }
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.4")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Safe array subscript extension
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
