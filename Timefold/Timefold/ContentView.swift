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
    @State private var isSelecting = false
    @State private var selectedAssets: Set<String> = []
    @State private var showingDeleteConfirmation = false

    private var isCompact: Bool {
        (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.width ?? 375) < 375
    }

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
                        MemoriesGridView(
                            assets: assets,
                            isGridViewMode: $viewMode,
                            isSelecting: $isSelecting,
                            selectedAssets: $selectedAssets,
                            showingDeleteConfirmation: $showingDeleteConfirmation
                        )
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
                    VStack(spacing: isCompact ? 0.5 : 1) {
                        HStack(spacing: isCompact ? 2 : 3) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: isCompact ? 13 : 15, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("Timefold")
                                .font(.system(size: isCompact ? 16 : 18, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        HStack(spacing: isCompact ? 2 : 3) {
                            Text(formatDateString(selectedDate))
                                .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            if !Calendar.current.isDateInToday(selectedDate) {
                                Button {
                                    selectedDate = Date()
                                    model.loadMemoriesFor(date: Date())
                                } label: {
                                    Text("• Today")
                                        .font(.system(size: isCompact ? 9 : 10, weight: .medium))
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
                    HStack(spacing: 12) {
                        // Calendar button (only in grid mode)
                        if viewMode == .grid {
                            Button {
                                showingDatePicker = true
                            } label: {
                                Image(systemName: "calendar")
                            }
                        }
                        
                        // View mode toggle button
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                // Clear selection when switching to fullscreen
                                if viewMode == .grid {
                                    isSelecting = false
                                    selectedAssets.removeAll()
                                }
                                viewMode = viewMode == .grid ? .fullscreen : .grid
                            }
                        } label: {
                            Image(systemName: viewMode == .grid ? "square.fill.on.square.fill" : "square.grid.3x3.fill")
                        }
                        
                        // Select/Delete buttons (only when in grid mode with loaded assets)
                        if case .loaded = model.state, viewMode == .grid {
                            if isSelecting {
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
        .confirmationDialog(
            "Delete \(selectedAssets.count) \(selectedAssets.count == 1 ? "item" : "items")?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if case .loaded(let assets) = model.state {
                    deleteSelectedPhotos(from: assets)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
    
    private func deleteSelectedPhotos(from assets: [PHAsset]) {
        let assetsToDelete = assets.filter { selectedAssets.contains($0.localIdentifier) }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    withAnimation {
                        // Clear selection and exit selection mode
                        selectedAssets.removeAll()
                        isSelecting = false
                        // Reload to update the view
                        model.loadMemoriesFor(date: selectedDate)
                    }
                } else if let error = error {
                    print("Error deleting photos: \(error.localizedDescription)")
                }
            }
        }
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
    @Binding var isSelecting: Bool
    @Binding var selectedAssets: Set<String>
    @Binding var showingDeleteConfirmation: Bool
    
    private let spacing: CGFloat = 2
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    
    @State private var deletedAssets: Set<String> = []
    @State private var isScrolling = false
    @State private var currentYear: Int?
    @State private var hideYearTask: Task<Void, Never>?
    @State private var lastYearChangeTime: Date = .distantPast

    var body: some View {
        ZStack {
            gridContent
            
            // Year badge overlay (only when scrolling)
            if let year = currentYear {
                VStack {
                    Spacer()
                    Text(String(year))
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.35))
                    Spacer()
                }
                .allowsHitTesting(false)
                .opacity(isScrolling ? 1.0 : 0.0)
                .animation(.easeIn(duration: 0.6), value: isScrolling)
            }
            
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
    }
    
    private var gridContent: some View {
        GeometryReader { geo in
            let cell = (geo.size.width - spacing * 2) / 3
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
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
                            .background(
                                GeometryReader { itemGeo in
                                    Color.clear
                                        .preference(
                                            key: ScrollOffsetPreferenceKey.self,
                                            value: itemGeo.frame(in: .named("scroll")).minY
                                        )
                                        .onAppear {
                                            updateYearIfVisible(itemGeo: itemGeo, asset: asset)
                                        }
                                        .onChange(of: itemGeo.frame(in: .named("scroll")).minY) { _ in
                                            updateYearIfVisible(itemGeo: itemGeo, asset: asset)
                                        }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 0)
            }
            .coordinateSpace(name: "scroll")
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .bottom)
        }
    }
    
    private func updateYearIfVisible(itemGeo: GeometryProxy, asset: PHAsset) {
        let frame = itemGeo.frame(in: .named("scroll"))
        
        // Only check items near the top of the screen (between 80-180 points from top)
        guard frame.minY > 80 && frame.minY < 180 else { return }
        
        guard let assetDate = asset.creationDate else { return }
        let year = Calendar.current.component(.year, from: assetDate)
        
        if currentYear != year {
            // Throttle year changes - only allow changes every 0.3 seconds
            let timeSinceLastChange = Date().timeIntervalSince(lastYearChangeTime)
            guard timeSinceLastChange > 0.3 else { return }
            
            lastYearChangeTime = Date()
            withAnimation(.easeInOut(duration: 0.2)) {
                currentYear = year
                isScrolling = true
            }
        } else if !isScrolling {
            withAnimation(.easeInOut(duration: 0.2)) {
                isScrolling = true
            }
        }
        
        // Cancel previous hide task and schedule new one
        hideYearTask?.cancel()
        hideYearTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isScrolling = false
                    }
                }
            }
        }
    }
    
    private func toggleSelection(for asset: PHAsset) {
        if selectedAssets.contains(asset.localIdentifier) {
            selectedAssets.remove(asset.localIdentifier)
        } else {
            selectedAssets.insert(asset.localIdentifier)
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
            DispatchQueue.main.async { self.image = img }
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
                // Share button
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
        makeStoryImage(from: image, asset: asset, canvasSize: CGSize(width: 1080, height: 1920))
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
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
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
                    // PHOTO VIEW with zoom and pan support
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        guard dragOffset == 0 else { return }
                                        let newScale = lastScale * value.magnification
                                        scale = min(max(newScale, 1.0), 4.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        if scale <= 1.0 {
                                            withAnimation(.spring(response: 0.3)) {
                                                scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
                                            }
                                        }
                                    }
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        guard dragOffset == 0 else { return }
                                        let newOffset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                        offset = constrainOffset(newOffset, scale: scale, geo: geo)
                                    }
                                    .onEnded { _ in lastOffset = offset },
                                including: scale > 1.0 ? .all : .none
                            )
                            .onTapGesture(count: 2) { location in
                                guard dragOffset == 0 else { return }
                                withAnimation(.spring(response: 0.3)) {
                                    if scale > 1.0 {
                                        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
                                    } else {
                                        scale = 2.0; lastScale = 2.0
                                        let tapPoint = CGPoint(
                                            x: location.x - geo.size.width / 2,
                                            y: location.y - geo.size.height / 2
                                        )
                                        offset = CGSize(width: -tapPoint.x * 0.5, height: -tapPoint.y * 0.5)
                                        lastOffset = offset
                                    }
                                }
                            }
                            .onChange(of: dragOffset) {
                                if dragOffset > 0 && scale != 1.0 {
                                    withAnimation(.spring(response: 0.2)) {
                                        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
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
    
    // Helper function to constrain the offset so the image doesn't pan too far
    private func constrainOffset(_ offset: CGSize, scale: CGFloat, geo: GeometryProxy) -> CGSize {
        guard scale > 1.0 else { return .zero }
        
        // Calculate the maximum allowed offset based on the zoom level
        let maxOffsetX = (geo.size.width * (scale - 1)) / 2
        let maxOffsetY = (geo.size.height * (scale - 1)) / 2
        
        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
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
            DispatchQueue.main.async {
                self.image = img
                if let img {
                    self.onImageReady(img)
                    Task.detached(priority: .utility) {
                        let storyImage = makeStoryImage(from: img, asset: self.asset, canvasSize: CGSize(width: 720, height: 1280))
                        await MainActor.run { self.onStoryImageReady(storyImage) }
                    }
                }
            }
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
        Task.detached(priority: .userInitiated) { [weak self] in
            let assets = Self.fetchMemories(for: date)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.state = assets.isEmpty ? .empty : .loaded(assets)
                if !assets.isEmpty {
                    SharedMemoriesManager.shared.saveMemoryCount(assets.count)
                    if let randomAsset = assets.randomElement() {
                        SharedMemoriesManager.shared.saveWidgetThumbnail(from: randomAsset)
                    }
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    static func fetchMemories(for date: Date) -> [PHAsset] {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let selectedYear = calendar.component(.year, from: date)

        var datePredicates: [NSPredicate] = []
        for year in 1970..<selectedYear {
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = day
            comps.hour = 0; comps.minute = 0; comps.second = 0
            guard let start = calendar.date(from: comps),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            datePredicates.append(
                NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            )
        }
        guard !datePredicates.isEmpty else { return [] }

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "mediaType == %d OR mediaType == %d",
                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue),
            NSCompoundPredicate(orPredicateWithSubpredicates: datePredicates)
        ])

        let results = PHAsset.fetchAssets(with: opts)
        return (0..<results.count).map { results.object(at: $0) }
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
        guard isEnabled else { return }

        let notifHour = Calendar.current.component(.hour, from: notificationTime)
        let notifMinute = Calendar.current.component(.minute, from: notificationTime)
        let minPhotos = minimumPhotos

        Task.detached(priority: .utility) {
            let calendar = Calendar.current
            let now = Date()
            var requests: [UNNotificationRequest] = []

            for daysAhead in 1...30 {
                guard let targetDate = calendar.date(byAdding: .day, value: daysAhead, to: now) else { continue }
                let month = calendar.component(.month, from: targetDate)
                let day = calendar.component(.day, from: targetDate)
                let year = calendar.component(.year, from: targetDate)

                let count = NotificationManager.countMemories(month: month, day: day, beforeYear: year)
                guard count >= minPhotos else { continue }

                var trigger = DateComponents()
                trigger.year = year; trigger.month = month; trigger.day = day
                trigger.hour = notifHour; trigger.minute = notifMinute

                let message = NotificationManager.notificationMessages.randomElement() ?? NotificationManager.notificationMessages[0]
                let content = UNMutableNotificationContent()
                content.title = message.0
                content.body = message.1
                content.sound = .default

                let id = "memoriesCheck_\(year)_\(String(format: "%02d", month))_\(String(format: "%02d", day))"
                requests.append(UNNotificationRequest(
                    identifier: id,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false)
                ))
            }

            let center = UNUserNotificationCenter.current()
            for request in requests { center.add(request) { _ in } }
        }
    }

    func cancelNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["dailyMemoriesCheck"])
    }

    private static func countMemories(month: Int, day: Int, beforeYear: Int) -> Int {
        let calendar = Calendar.current
        var datePredicates: [NSPredicate] = []
        for year in 1970..<beforeYear {
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = day
            comps.hour = 0; comps.minute = 0; comps.second = 0
            guard let start = calendar.date(from: comps),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            datePredicates.append(
                NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            )
        }
        guard !datePredicates.isEmpty else { return 0 }
        let opts = PHFetchOptions()
        opts.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "mediaType == %d OR mediaType == %d",
                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue),
            NSCompoundPredicate(orPredicateWithSubpredicates: datePredicates)
        ])
        opts.includeHiddenAssets = false
        return PHAsset.fetchAssets(with: opts).count
    }

    private static let notificationMessages: [(String, String)] = [
        ("Your memories are ready", "Photos from this day in past years"),
        ("Time to look back", "See what you were up to today"),
        ("Memories from this day", "Tap to revisit the past"),
        ("Your past awaits", "Photos from years ago are waiting"),
        ("Ready to revisit today?", "See how this day looked before"),
        ("Take a moment to look back", "Your photos from this day"),
        ("What were you doing on this day?", "Find out in your memories"),
        ("See what you were up to", "Photos from this day over the years")
    ]
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
                    Text("Get a daily notification only on days when you have enough memories. Scheduled up to 30 days ahead each time you open the app.")
                }
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
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

// MARK: - Shared Story Image Renderer

private func makeStoryImage(from image: UIImage, asset: PHAsset, canvasSize: CGSize) -> UIImage? {
    let scale = canvasSize.width / 1080.0

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

    return renderer.image { context in
        let ctx = context.cgContext

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0).cgColor,
            UIColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0).cgColor
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) else { return }
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: canvasSize.width, y: canvasSize.height), options: [])

        let maxPhotoWidth = 900 * scale
        let maxPhotoHeight = 1320 * scale
        let photoY = 300 * scale

        let imageAspect = image.size.width / image.size.height
        let photoRect: CGRect
        if imageAspect > maxPhotoWidth / maxPhotoHeight {
            let width = maxPhotoWidth
            let height = width / imageAspect
            photoRect = CGRect(x: (canvasSize.width - width) / 2, y: photoY, width: width, height: height)
        } else {
            let height = maxPhotoHeight
            let width = height * imageAspect
            photoRect = CGRect(x: (canvasSize.width - width) / 2, y: photoY, width: width, height: height)
        }

        let logoY = 120 * scale
        let badgeCornerRadius = 32 * scale
        let badgePadding = 32 * scale
        let clockRadius = 42 * scale
        let dividerSpacing = 32 * scale
        let dividerWidth = 4 * scale
        let fontSize = 58 * scale
        let kern = 10 * scale

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .black),
            .foregroundColor: UIColor.white,
            .kern: kern
        ]
        let text = "TIMEFOLD" as NSString
        let textSize = text.size(withAttributes: textAttrs)

        let badgeContentWidth = clockRadius * 2 + dividerSpacing + dividerWidth + dividerSpacing + textSize.width
        let badgeContentHeight = max(clockRadius * 2, textSize.height)
        let badgeWidth = badgeContentWidth + badgePadding * 2
        let badgeHeight = badgeContentHeight + badgePadding * 2
        let badgeX = (canvasSize.width - badgeWidth) / 2
        let badgeRect = CGRect(x: badgeX, y: logoY, width: badgeWidth, height: badgeHeight)

        ctx.setShadow(offset: CGSize(width: 0, height: 3 * scale), blur: 10 * scale, color: UIColor.black.withAlphaComponent(0.15).cgColor)
        UIColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 0.35).setFill()
        UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeCornerRadius).fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        let clockCX = badgeX + badgePadding + clockRadius
        let clockCY = logoY + badgeHeight / 2

        UIColor.white.withAlphaComponent(0.65).setStroke()
        let clockPath = UIBezierPath(arcCenter: CGPoint(x: clockCX, y: clockCY), radius: clockRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        clockPath.lineWidth = 5 * scale
        clockPath.stroke()

        let hourPath = UIBezierPath()
        hourPath.move(to: CGPoint(x: clockCX, y: clockCY))
        hourPath.addLine(to: CGPoint(x: clockCX, y: clockCY - clockRadius * 0.6))
        hourPath.lineWidth = 5 * scale
        hourPath.lineCapStyle = .round
        UIColor.white.withAlphaComponent(0.65).setStroke()
        hourPath.stroke()

        let minutePath = UIBezierPath()
        minutePath.move(to: CGPoint(x: clockCX, y: clockCY))
        minutePath.addLine(to: CGPoint(x: clockCX + clockRadius * 0.5, y: clockCY + clockRadius * 0.2))
        minutePath.lineWidth = 4.5 * scale
        minutePath.lineCapStyle = .round
        UIColor.white.withAlphaComponent(0.65).setStroke()
        minutePath.stroke()

        UIColor.white.withAlphaComponent(0.65).setFill()
        UIBezierPath(arcCenter: CGPoint(x: clockCX, y: clockCY), radius: 5.5 * scale, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()

        let dividerX = clockCX + clockRadius + dividerSpacing
        let dividerHeight = badgeContentHeight * 0.6
        let divPath = UIBezierPath()
        divPath.move(to: CGPoint(x: dividerX, y: clockCY - dividerHeight / 2))
        divPath.addLine(to: CGPoint(x: dividerX, y: clockCY + dividerHeight / 2))
        divPath.lineWidth = dividerWidth
        UIColor.white.withAlphaComponent(0.65).setStroke()
        divPath.stroke()

        let subtleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .black),
            .foregroundColor: UIColor.white.withAlphaComponent(0.65),
            .kern: kern
        ]
        text.draw(at: CGPoint(x: dividerX + dividerSpacing, y: clockCY - textSize.height / 2), withAttributes: subtleAttrs)

        let borderRect = photoRect.insetBy(dx: -30 * scale, dy: -30 * scale)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.setShadow(offset: CGSize(width: 0, height: 15 * scale), blur: 45 * scale, color: UIColor.black.withAlphaComponent(0.3).cgColor)
        UIBezierPath(roundedRect: borderRect, cornerRadius: 24 * scale).fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        ctx.saveGState()
        UIBezierPath(roundedRect: photoRect, cornerRadius: 18 * scale).addClip()
        image.draw(in: photoRect)
        ctx.restoreGState()

        let dateText = storyFormattedDate(asset.creationDate) as NSString
        let yearsText = storyYearsAgo(asset.creationDate) as NSString

        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 72 * scale, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let dateSize = dateText.size(withAttributes: dateAttrs)
        ctx.setShadow(offset: CGSize(width: 0, height: 4 * scale), blur: 12 * scale, color: UIColor.black.withAlphaComponent(0.3).cgColor)
        dateText.draw(at: CGPoint(x: (canvasSize.width - dateSize.width) / 2, y: photoRect.maxY + 75 * scale), withAttributes: dateAttrs)

        let yearsAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 54 * scale, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.9)
        ]
        let yearsSize = yearsText.size(withAttributes: yearsAttrs)
        yearsText.draw(at: CGPoint(x: (canvasSize.width - yearsSize.width) / 2, y: photoRect.maxY + 165 * scale), withAttributes: yearsAttrs)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
    }
}

private func storyFormattedDate(_ date: Date?) -> String {
    guard let date else { return "" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM d, yyyy"
    return formatter.string(from: date)
}

private func storyYearsAgo(_ date: Date?) -> String {
    guard let date else { return "" }
    let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
    if years <= 0 { return "Today" }
    if years == 1 { return "1 year ago today" }
    return "\(years) years ago today"
}
