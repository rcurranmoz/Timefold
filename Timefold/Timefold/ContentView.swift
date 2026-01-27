import SwiftUI
import Photos
import Combine
import UIKit

struct ContentView: View {
    @StateObject private var model = MemoriesViewModel()
    @State private var viewMode: ViewMode = .grid
    
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
                        MemoriesGridView(assets: assets)
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
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("Timefold")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        Text(todayDateString())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    // View mode toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewMode = viewMode == .grid ? .fullscreen : .grid
                        }
                    } label: {
                        Image(systemName: viewMode == .grid ? "square.fill.on.square.fill" : "square.grid.3x3.fill")
                    }
                }
            }
        }
        .task {
            model.start()
        }
    }
    
    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: Date())
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
    private let spacing: CGFloat = 2
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    
    @State private var deletedAssets: Set<String> = []
    @State private var assetToDelete: PHAsset?
    @State private var showingDeleteAlert = false
    @State private var visibleYear: Int?
    @State private var showYear = false
    @State private var hideYearTask: DispatchWorkItem?
    @State private var lastYearUpdate: Date = .distantPast
    
    init(assets: [PHAsset]) {
        self.assets = assets
        // Initialize to first year
        if let firstAsset = assets.first,
           let date = firstAsset.creationDate {
            let year = Calendar.current.component(.year, from: date)
            _visibleYear = State(initialValue: year)
        }
    }

    var body: some View {
        ZStack {
            gridContent
            
            // Floating year indicator
            if showYear, let year = visibleYear {
                VStack {
                    Spacer()
                    Text(String(year))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.5), value: showYear)
                }
                .padding(.bottom, 80)
            }
        }
        .alert("Delete Photo?", isPresented: $showingDeleteAlert, presenting: assetToDelete) { asset in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePhoto(asset: asset)
            }
        } message: { asset in
            deleteMessage(for: asset)
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
                                onDelete: {
                                    assetToDelete = asset
                                    showingDeleteAlert = true
                                }
                            )
                            .background(
                                GeometryReader { itemGeo in
                                    Color.clear
                                        .onChange(of: itemGeo.frame(in: .named("scroll")).minY) { _ in
                                            let frame = itemGeo.frame(in: .named("scroll"))
                                            updateVisibleYear(for: asset, frame: frame, in: geo.size.height)
                                        }
                                        .onAppear {
                                            let frame = itemGeo.frame(in: .named("scroll"))
                                            updateVisibleYear(for: asset, frame: frame, in: geo.size.height)
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
        }
    }
    
    private func updateVisibleYear(for asset: PHAsset, frame: CGRect, in viewHeight: CGFloat) {
        // Check if item is near the TOP of the screen (first 20% of viewport)
        let topZone = viewHeight * 0.2
        
        if frame.minY >= 0 && frame.minY <= topZone {
            if let date = asset.creationDate {
                let year = Calendar.current.component(.year, from: date)
                
                // If year changed, throttle updates to prevent glitchiness
                if visibleYear != year {
                    let now = Date()
                    let timeSinceLastUpdate = now.timeIntervalSince(lastYearUpdate)
                    
                    // Only update if enough time has passed (0.5 seconds)
                    guard timeSinceLastUpdate > 0.5 else { return }
                    
                    lastYearUpdate = now
                    
                    // Gentle fade out
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showYear = false
                    }
                    
                    // Update year and fade in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        visibleYear = year
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showYear = true
                        }
                        
                        // Cancel existing hide task
                        hideYearTask?.cancel()
                        
                        // Schedule new hide task
                        let task = DispatchWorkItem {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showYear = false
                            }
                        }
                        hideYearTask = task
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
                    }
                } else if !showYear {
                    // Just show the year if it's not currently visible
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showYear = true
                    }
                    
                    // Cancel existing hide task
                    hideYearTask?.cancel()
                    
                    // Schedule new hide task
                    let task = DispatchWorkItem {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showYear = false
                        }
                    }
                    hideYearTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
                }
            }
        }
    }
    
    private func deleteMessage(for asset: PHAsset) -> Text {
        if let date = asset.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return Text("Photo from \(formatter.string(from: date)) will be permanently deleted.")
        } else {
            return Text("This photo will be permanently deleted.")
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
    let onDelete: () -> Void
    
    var body: some View {
        NavigationLink {
            MemoryPagerView(assets: assets, startAsset: asset)
        } label: {
            AssetThumbnailView(asset: asset)
                .frame(width: cellSize, height: cellSize)
                .clipped()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Photo", systemImage: "trash")
            }
        }
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
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var storyImages: [String: UIImage] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @GestureState private var dragState: CGFloat = 0
    
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
            .tabViewStyle(.page(indexDisplayMode: .automatic))
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
                .disabled(currentImage == nil)
                .opacity(dragOffset > 20 ? 0 : 1)
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear {
            if let i = assets.firstIndex(where: { $0.localIdentifier == startAsset.localIdentifier }) {
                selection = i
            }
        }
        .sheet(isPresented: $showingShare) {
            if let storyImage = currentStoryImage {
                ActivityView(activityItems: [storyImage])
            } else if let currentImage, let asset = currentAsset {
                // Fallback if story image not ready yet
                let storyImage = createStoryImage(from: currentImage, asset: asset) ?? currentImage
                ActivityView(activityItems: [storyImage])
            } else {
                ActivityView(activityItems: ["Memory"])
            }
        }
    }
    
    private func createStoryImage(from image: UIImage, asset: PHAsset) -> UIImage? {
        // Create a canvas sized for Instagram stories (9:16 aspect ratio)
        let storySize = CGSize(width: 720, height: 1280)
        
        let renderer = UIGraphicsImageRenderer(size: storySize)
        
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
            let maxPhotoWidth = storySize.width - 120
            let maxPhotoHeight = storySize.height - 400
            
            let imageAspect = image.size.width / image.size.height
            let photoRect: CGRect
            
            if imageAspect > maxPhotoWidth / maxPhotoHeight {
                // Width constrained
                let width = maxPhotoWidth
                let height = width / imageAspect
                photoRect = CGRect(
                    x: (storySize.width - width) / 2,
                    y: 200,
                    width: width,
                    height: height
                )
            } else {
                // Height constrained
                let height = maxPhotoHeight
                let width = height * imageAspect
                photoRect = CGRect(
                    x: (storySize.width - width) / 2,
                    y: 200,
                    width: width,
                    height: height
                )
            }
            
            // Draw white border around photo
            let borderRect = photoRect.insetBy(dx: -20, dy: -20)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            ctx.fill(borderRect)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            
            // Draw the photo
            image.draw(in: photoRect)
            
            // Text overlay at bottom
            let dateText = formattedDateForStory(asset.creationDate)
            let yearsText = yearsAgoForStory(asset.creationDate)
            
            // App name at top
            let appNameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let appName = "Timefold" as NSString
            let appNameSize = appName.size(withAttributes: appNameAttrs)
            appName.draw(
                at: CGPoint(x: (storySize.width - appNameSize.width) / 2, y: 80),
                withAttributes: appNameAttrs
            )
            
            // Date text
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let dateString = dateText as NSString
            let dateSize = dateString.size(withAttributes: dateAttrs)
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

    var body: some View {
        GeometryReader { geo in
            ZStack {
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
                        .onAppear {
                            onImageReady(image)
                            // Generate story image in background
                            Task.detached(priority: .utility) {
                                let storyImage = await createStoryImageAsync(from: image, asset: asset)
                                await MainActor.run {
                                    onStoryImageReady(storyImage)
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
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color.black)
        }
        .task {
            await loadFull()
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
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: UIColor.black.withAlphaComponent(0.3).cgColor)
                ctx.fill(borderRect)
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
                
                image.draw(in: photoRect)
                
                let dateText = self.formattedDateForStory(asset.creationDate)
                let yearsText = self.yearsAgoForStory(asset.creationDate)
                
                let appNameAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let appName = "Timefold" as NSString
                let appNameSize = appName.size(withAttributes: appNameAttrs)
                appName.draw(
                    at: CGPoint(x: (storySize.width - appNameSize.width) / 2, y: 80),
                    withAttributes: appNameAttrs
                )
                
                let dateAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let dateString = dateText as NSString
                let dateSize = dateString.size(withAttributes: dateAttrs)
                dateString.draw(
                    at: CGPoint(x: (storySize.width - dateSize.width) / 2, y: photoRect.maxY + 50),
                    withAttributes: dateAttrs
                )
                
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
        state = .loading

        let calendar = Calendar.current
        let now = Date()
        let day = calendar.component(.day, from: now)
        let month = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let results = PHAsset.fetchAssets(with: fetchOptions)

        var assets: [PHAsset] = []
        
        // Iterate in order to preserve the sort
        for i in 0..<results.count {
            let asset = results.object(at: i)
            guard let date = asset.creationDate else { continue }
            let aDay = calendar.component(.day, from: date)
            let aMonth = calendar.component(.month, from: date)
            let aYear = calendar.component(.year, from: date)

            guard aYear < currentYear else { continue }

            if aDay == day && aMonth == month {
                assets.append(asset)
            }
        }

        DispatchQueue.main.async {
            // Debug: print first few years
            if !assets.isEmpty {
                print("📅 First asset year:", Calendar.current.component(.year, from: assets.first?.creationDate ?? Date()))
                if assets.count > 1 {
                    print("📅 Second asset year:", Calendar.current.component(.year, from: assets[1].creationDate ?? Date()))
                }
                if assets.count > 2 {
                    print("📅 Third asset year:", Calendar.current.component(.year, from: assets[2].creationDate ?? Date()))
                }
            }
            self.state = assets.isEmpty ? .empty : .loaded(assets)
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
        controller.completionWithItemsHandler = { _, _, _, _ in
            presentationMode.wrappedValue.dismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Scroll Tracking
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Safe array subscript extension
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
