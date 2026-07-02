import SwiftUI
import Photos
import Combine
import UIKit
import UserNotifications
import WidgetKit
import AVKit

// MARK: - Theme
// Single source of truth for Timefold's visual identity: warm, tactile,
// scrapbook-y. Every branded surface (reveal, loading, empty, permission)
// shares one "sky" that follows the time of day, so opening the app at dawn
// feels different from opening it at midnight — but always cozy.
enum Theme {
    // Brand palette
    static let pink   = Color(red: 1.00, green: 0.18, blue: 0.33)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.00)
    static let cream  = Color(red: 0.99, green: 0.96, blue: 0.90)
    static let mat    = Color(red: 1.00, green: 0.99, blue: 0.96) // polaroid card stock
    static let ink    = Color(red: 0.27, green: 0.17, blue: 0.19) // warm near-black
    static let inkSoft = Color(red: 0.48, green: 0.35, blue: 0.37)

    static let brandGradient = LinearGradient(
        colors: [orange, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum Daypart { case sunrise, day, dusk, night }

    static func daypart(for date: Date = Date()) -> Daypart {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11:  return .sunrise
        case 11..<17: return .day
        case 17..<21: return .dusk
        default:      return .night
        }
    }

    /// Warm backdrop that follows the time of day. Night is a cozy plum, not
    /// a void — the app should feel like a lit room, never a server rack.
    static func sky(for date: Date = Date()) -> LinearGradient {
        let colors: [Color]
        switch daypart(for: date) {
        case .sunrise:
            colors = [Color(red: 1.00, green: 0.95, blue: 0.86),
                      Color(red: 1.00, green: 0.87, blue: 0.80),
                      Color(red: 0.98, green: 0.80, blue: 0.82)]
        case .day:
            colors = [Color(red: 1.00, green: 0.97, blue: 0.88),
                      Color(red: 1.00, green: 0.91, blue: 0.79),
                      Color(red: 0.99, green: 0.84, blue: 0.78)]
        case .dusk:
            colors = [Color(red: 0.99, green: 0.87, blue: 0.76),
                      Color(red: 0.98, green: 0.75, blue: 0.72),
                      Color(red: 0.87, green: 0.68, blue: 0.82)]
        case .night:
            colors = [Color(red: 0.20, green: 0.13, blue: 0.26),
                      Color(red: 0.28, green: 0.15, blue: 0.28),
                      Color(red: 0.36, green: 0.21, blue: 0.30)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    static func isNightSky(for date: Date = Date()) -> Bool {
        daypart(for: date) == .night
    }

    /// Primary / secondary text colors that read on the current sky.
    static func skyInk(for date: Date = Date()) -> Color {
        isNightSky(for: date) ? cream : ink
    }
    static func skyInkSoft(for date: Date = Date()) -> Color {
        isNightSky(for: date) ? cream.opacity(0.72) : inkSoft
    }
}

extension Font {
    /// Serif face for dates & headlines — the "memory" voice.
    static func timefoldSerif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Rounded face for meta labels, hints, and companion dialogue.
    static func timefoldRounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Text {
    /// Kerned, small-caps-feeling meta label in the brand voice.
    func metaLabel(_ size: CGFloat = 12, color: Color = Theme.inkSoft) -> some View {
        self.font(.timefoldRounded(size))
            .kerning(2.4)
            .foregroundStyle(color)
    }
}

/// Lightweight haptics helper for the reveal beats & interactions.
enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

/// Animated skeleton placeholder shown while a thumbnail loads.
struct ShimmerView: View {
    @State private var phase: CGFloat = -1
    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .secondarySystemFill))
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.35), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: w * 0.6)
                    .offset(x: phase * w * 1.6)
                }
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - Hero zoom transition (iOS 18+, graceful no-op on iOS 17)
private struct HeroSource: ViewModifier {
    let id: String
    let ns: Namespace.ID
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: ns)
        } else {
            content
        }
    }
}

private struct HeroDestination: ViewModifier {
    let id: String
    let ns: Namespace.ID
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            content
        }
    }
}

extension View {
    func heroSource(_ id: String, _ ns: Namespace.ID) -> some View {
        modifier(HeroSource(id: id, ns: ns))
    }
    func heroDestination(_ id: String, _ ns: Namespace.ID) -> some View {
        modifier(HeroDestination(id: id, ns: ns))
    }
}

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
    @State private var showingReveal = false

    private var isCompact: Bool {
        (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.width ?? 375) < 375
    }

    /// Whether the toolbar chrome (wordmark, gear, calendar…) has anything to
    /// act on. Branded full-screen states carry their own identity.
    private var hasContent: Bool {
        switch model.state {
        case .loaded, .empty: return true
        default: return false
        }
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
                    BrandedLoadingView()

                case .empty:
                    EmptyMemoriesView(date: selectedDate)

                case .loaded(let assets):
                    if viewMode == .grid {
                        MemoriesGridView(
                            assets: assets,
                            isRevealActive: showingReveal,
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
            // While the daily reveal is up, the app waits out of focus behind
            // it; when the reveal lifts, everything settles sharp. One scene,
            // not two screens.
            .scaleEffect(showingReveal ? 1.06 : 1)
            .blur(radius: showingReveal ? 14 : 0)
            .animation(.easeInOut(duration: 0.55), value: showingReveal)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Gate at the ToolbarItem level: on branded full-screen
                // states even an *empty* item renders its glass container.
                if hasContent {
                ToolbarItem(placement: .principal) {
                        VStack(spacing: isCompact ? 0.5 : 1) {
                            BrandWordmark(isCompact: isCompact)
                            HStack(spacing: isCompact ? 2 : 3) {
                                Text(formatDateString(selectedDate))
                                    .font(.system(size: isCompact ? 9 : 11, weight: .medium))
                                    .foregroundStyle(.secondary)

                                if !Calendar.current.isDateInToday(selectedDate) {
                                    Button {
                                        selectedDate = Date()
                                        model.loadMemoriesFor(date: Date())
                                    } label: {
                                        Text("• Today")
                                            .font(.system(size: isCompact ? 9 : 11, weight: .medium))
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

                        // View mode toggle & select/delete only make sense
                        // once memories are actually loaded
                        if case .loaded = model.state {
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

                            // Select/Delete buttons (only in grid mode)
                            if viewMode == .grid {
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
                } // if hasContent
            }
            .toolbarBackground(hasContent ? .visible : .hidden, for: .navigationBar)
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
        .onChange(of: model.state) { newState in
            switch newState {
            case .loaded:
                if shouldShowReveal() {
                    showingReveal = true
                } else {
                    promptNotificationsIfNeeded()
                }
            case .empty:
                promptNotificationsIfNeeded()
            default:
                break
            }
        }
        .overlay {
            if showingReveal, case .loaded(let assets) = model.state {
                DailyRevealView(assets: assets, date: selectedDate) {
                    markRevealShown()
                    withAnimation(.easeInOut(duration: 0.55)) {
                        showingReveal = false
                    }
                    // First launch only: once the reveal has landed, ask about
                    // the daily reminder — after the moment, never during it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        promptNotificationsIfNeeded()
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
    }

    /// One-shot, first-session notification ask. If granted, the daily
    /// reminder turns itself on with sensible defaults (9 AM, 3+ photos) —
    /// permission without a scheduled reminder would be a no-op.
    private func promptNotificationsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "didPromptForNotifications") else { return }
        UserDefaults.standard.set(true, forKey: "didPromptForNotifications")
        notificationManager.promptInitialPermission()
    }

    private func shouldShowReveal() -> Bool {
        #if DEBUG
        return true
        #else
        guard Calendar.current.isDateInToday(selectedDate) else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        guard let last = UserDefaults.standard.object(forKey: "lastRevealDate") as? Date else { return true }
        return Calendar.current.startOfDay(for: last) < today
        #endif
    }

    private func markRevealShown() {
        UserDefaults.standard.set(Date(), forKey: "lastRevealDate")
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

// MARK: - Brand Wordmark (animated)
private struct BrandWordmark: View {
    let isCompact: Bool
    @State private var shimmer = false

    private var glyphs: some View {
        HStack(spacing: isCompact ? 2 : 3) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: isCompact ? 13 : 16, weight: .semibold))
            Text("Timefold")
                .font(.system(size: isCompact ? 16 : 20, weight: .bold, design: .rounded))
        }
        .fixedSize()
    }

    var body: some View {
        glyphs
            .foregroundStyle(Theme.brandGradient)
            .overlay {
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.85), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: w * 0.45)
                    .offset(x: shimmer ? w * 1.1 : -w * 0.55)
                    .blendMode(.plusLighter)
                }
                .mask(glyphs)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: false).delay(1.0)) {
                    shimmer = true
                }
            }
    }
}

private struct PermissionView: View {
    let onRequest: () -> Void
    @State private var appeared = false
    @AppStorage(mascotStorageKey) private var mascotRaw = MascotKind.foldy.rawValue

    private var ink: Color { Theme.skyInk() }
    private var inkSoft: Color { Theme.skyInkSoft() }

    var body: some View {
        ZStack {
            Theme.sky().ignoresSafeArea()
            SunGlow()

            VStack(spacing: 0) {
                Spacer()

                // Your companion says hello before asking for anything.
                TimeSprite(mood: .happy, kind: MascotKind(rawValue: mascotRaw) ?? .foldy)
                    .scaleEffect(0.85, anchor: .bottom)
                    .frame(height: 190)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.7, anchor: .bottom)
                    .animation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.1), value: appeared)

                VStack(spacing: 12) {
                    Text("Remember this")
                        .multilineTextAlignment(.center)
                        .font(.timefoldSerif(40))
                        .foregroundStyle(ink)
                    Text("PHOTOS FROM THIS DAY,\nEVERY PAST YEAR")
                        .metaLabel(11, color: inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.top, 30)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(.easeOut(duration: 0.5).delay(0.05), value: appeared)

                Spacer()

                VStack(spacing: 18) {
                    Button(action: onRequest) {
                        Text("Open My Memories")
                            .font(.timefoldRounded(17, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.brandGradient)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .shadow(color: Theme.pink.opacity(0.35), radius: 16, y: 8)
                    }

                    VStack(spacing: 4) {
                        Label("100% Private", systemImage: "lock.shield.fill")
                            .font(.timefoldRounded(12))
                            .foregroundStyle(inkSoft)
                        Text("No accounts • No ads • Nothing leaves your device")
                            .font(.system(size: 11))
                            .foregroundStyle(inkSoft.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 380)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.45), value: appeared)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Shared warm ornaments

/// A soft radial "sun" hanging in the sky behind hero content.
private struct SunGlow: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(Theme.isNightSky() ? 0.14 : 0.55), .clear],
                    center: .center, startRadius: 10, endRadius: 260
                )
            )
            .frame(width: 520, height: 520)
            .offset(y: -140)
            .allowsHitTesting(false)
    }
}

/// Classic polaroid: white mat, square photo window, handwritten-ish caption.
private struct PolaroidFrame<Photo: View>: View {
    var caption: String?
    var photoSize: CGFloat = 114
    @ViewBuilder let photo: Photo

    var body: some View {
        VStack(spacing: 0) {
            photo
                .frame(width: photoSize, height: photoSize)
                .clipShape(Rectangle())
            ZStack {
                if let caption {
                    Text(caption)
                        .font(.timefoldSerif(photoSize * 0.13, weight: .semibold))
                        .italic()
                        .foregroundStyle(Theme.ink.opacity(0.7))
                }
            }
            .frame(width: photoSize, height: photoSize * 0.28)
        }
        .padding([.top, .horizontal], photoSize * 0.075)
        .background(Theme.mat)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}

// MARK: - Branded States
private struct BrandedLoadingView: View {
    @State private var breathe = false
    @State private var pulse = false

    /// Warm placeholder "photos" inside the stacked polaroids.
    private let windows: [[Color]] = [
        [Color(red: 0.55, green: 0.72, blue: 0.95), Color(red: 0.80, green: 0.62, blue: 0.92)],
        [Color(red: 1.00, green: 0.80, blue: 0.45), Color(red: 0.98, green: 0.52, blue: 0.45)],
        [Theme.orange, Theme.pink],
    ]

    var body: some View {
        ZStack {
            Theme.sky().ignoresSafeArea()
            SunGlow()

            VStack(spacing: 26) {
                // A held stack of polaroids, breathing apart — the hand the
                // reveal is about to deal.
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        let t = Double(i - 1)
                        PolaroidFrame(caption: nil, photoSize: 104) {
                            LinearGradient(colors: windows[i],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                        .rotationEffect(.degrees(t * (breathe ? 10 : 5)), anchor: .bottom)
                        .offset(x: t * (breathe ? 14 : 7), y: abs(t) * 3)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(Double(i) * 0.08),
                            value: breathe
                        )
                        .zIndex(Double(i))
                    }

                }
                .frame(height: 190)
                .overlay(alignment: .bottom) {
                    // Clock badge tucked onto the stack's lower-right corner
                    ZStack {
                        Circle()
                            .fill(Theme.mat)
                            .frame(width: 46, height: 46)
                            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.brandGradient)
                    }
                    .offset(x: 62, y: -26)
                }

                Text("GATHERING YOUR MEMORIES")
                    .metaLabel(11, color: Theme.skyInkSoft())
                    .opacity(pulse ? 1 : 0.45)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            }
        }
        .onAppear {
            breathe = true
            pulse = true
        }
    }
}

private struct EmptyMemoriesView: View {
    let date: Date
    @State private var appeared = false
    @AppStorage(mascotStorageKey) private var mascotRaw = MascotKind.foldy.rawValue

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "MMMM d"; return f.string(from: date)
    }

    var body: some View {
        ZStack {
            Theme.sky(for: Date()).ignoresSafeArea()
            SunGlow()
            VStack(spacing: 10) {
                TimeSprite(mood: .sleepy, kind: MascotKind(rawValue: mascotRaw) ?? .foldy)
                    .scaleEffect(0.62)
                    .frame(height: 150)
                Text(dateString)
                    .font(.timefoldSerif(38))
                    .foregroundStyle(Theme.skyInk())
                Text("NO MEMORIES ON THIS DAY YET")
                    .metaLabel(11, color: Theme.skyInkSoft())
                Text("Today's photos become next year's memories.\nGo make one worth keeping.")
                    .font(.timefoldRounded(14, weight: .medium))
                    .foregroundStyle(Theme.skyInkSoft().opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
                    .padding(.top, 6)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.easeOut(duration: 0.5), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

private struct MemoriesGridView: View {
    let assets: [PHAsset]
    var isRevealActive: Bool = false
    @Binding var isGridViewMode: ContentView.ViewMode
    @Binding var isSelecting: Bool
    @Binding var selectedAssets: Set<String>
    @Binding var showingDeleteConfirmation: Bool

    private let spacing: CGFloat = 2
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    @AppStorage("showFloatingYear") private var showFloatingYear: Bool = true

    @Namespace private var heroNS
    @State private var entered = false
    @State private var deletedAssets: Set<String> = []
    @State private var isScrolling = false
    @State private var currentYear: Int?
    @State private var hideYearTask: Task<Void, Never>?
    @State private var lastYearChangeTime: Date = .distantPast

    var body: some View {
        ZStack {
            gridContent
            
            // Year badge overlay (only when scrolling)
            if showFloatingYear, let year = currentYear {
                VStack {
                    Spacer()
                    Text(String(year))
                        .font(.timefoldSerif(84))
                        .foregroundStyle(.primary.opacity(0.32))
                        .shadow(color: Color(uiColor: .systemBackground).opacity(0.6), radius: 12)
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
                                namespace: heroNS,
                                onToggleSelection: { toggleSelection(for: asset) },
                                onDelete: { deletePhoto(asset: asset) }
                            )
                            // Cascade the first screenful in when the reveal
                            // lifts; cells created later mount already-entered.
                            .opacity(entered ? 1 : 0)
                            .scaleEffect(entered ? 1 : 0.88)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(min(Double(index) * 0.025, 0.45)),
                                value: entered
                            )
                            .background(
                                GeometryReader { itemGeo in
                                    Color.clear
                                        .preference(
                                            key: ScrollOffsetPreferenceKey.self,
                                            value: itemGeo.frame(in: .named("scroll")).minY
                                        )
                                        .onAppear { updateYearIfVisible(itemGeo: itemGeo, asset: asset) }
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
            .onAppear {
                if !isRevealActive { entered = true }
            }
            .onChange(of: isRevealActive) {
                if !isRevealActive { entered = true }
            }
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
    let namespace: Namespace.ID
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
                        .heroDestination(asset.localIdentifier, namespace)
                } label: {
                    cellContent
                }
                .buttonStyle(.plain)
                .heroSource(asset.localIdentifier, namespace)
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
    var targetSize: CGSize = CGSize(width: 300, height: 300)
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                ShimmerView()
            }
        }
        .animation(.easeOut(duration: 0.35), value: image == nil)
        .task {
            await load()
        }
    }

    private func load() async {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
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
    @AppStorage("shareWithFrame") private var shareWithFrame: Bool = true

    @State private var selection: Int = 0
    @State private var showingShare = false
    @State private var isPreparingShare = false
    @State private var shareItem: ShareItem?
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var storyImages: [String: UIImage] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var isZoomed = false
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
                        dragOffset: dragOffset,
                        onZoomChanged: { isZoomed = $0 }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: currentAssetIsVideo ? .never : .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .offset(y: dragOffset)
            .opacity(opacity)
            .onChange(of: selection) { isZoomed = false }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        // While a photo is zoomed in, the child owns all panning —
                        // stand down so dragging the photo doesn't trigger dismiss.
                        guard !isZoomed else { return }
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
                        guard !isZoomed else { return }
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
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                            .shadow(color: .black.opacity(0.25), radius: 1)
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
                    } else if !shareWithFrame, let currentImage {
                        await MainActor.run {
                            shareItem = .image(currentImage)
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
    var onZoomChanged: (Bool) -> Void = { _ in }

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
                            // Pan takes priority over the TabView's paging swipe, but
                            // only while zoomed in (otherwise paging works normally).
                            .highPriorityGesture(
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
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        guard dragOffset == 0 else { return }
                                        let newScale = lastScale * value.magnification
                                        scale = min(max(newScale, 1.0), 4.0)
                                        // Keep the pan inside bounds as we zoom out.
                                        offset = constrainOffset(offset, scale: scale, geo: geo)
                                    }
                                    .onEnded { _ in
                                        if scale <= 1.0 {
                                            withAnimation(.spring(response: 0.3)) {
                                                scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
                                            }
                                        } else {
                                            lastScale = scale
                                            lastOffset = offset
                                        }
                                        reportZoom()
                                    }
                            )
                            .onTapGesture(count: 2) { location in
                                guard dragOffset == 0 else { return }
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    if scale > 1.0 {
                                        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
                                    } else {
                                        let targetScale: CGFloat = 2.5
                                        scale = targetScale; lastScale = targetScale
                                        // Center the tapped point, then clamp to valid bounds.
                                        let tapPoint = CGPoint(
                                            x: location.x - geo.size.width / 2,
                                            y: location.y - geo.size.height / 2
                                        )
                                        let raw = CGSize(width: -tapPoint.x * (targetScale - 1),
                                                         height: -tapPoint.y * (targetScale - 1))
                                        offset = constrainOffset(raw, scale: targetScale, geo: geo)
                                        lastOffset = offset
                                    }
                                }
                                reportZoom()
                            }
                            .onChange(of: dragOffset) {
                                if dragOffset > 0 && scale != 1.0 {
                                    withAnimation(.spring(response: 0.2)) {
                                        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
                                    }
                                    reportZoom()
                                }
                            }
                    } else {
                        ProgressView("Loading…")
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(ambientBackdrop)
        }
        .task {
            await loadFull()
        }
        .onDisappear {
            player?.pause()
            player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            onZoomChanged(false)
        }
    }
    
    // Ambient backdrop: a heavily blurred, darkened copy of the current photo
    // instead of a flat black void — the Apple Music / Photos full-screen feel.
    @ViewBuilder
    private var ambientBackdrop: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60, opaque: true)
                    .overlay(Color.black.opacity(0.45))
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.4), value: image == nil)
    }

    private func reportZoom() {
        onZoomChanged(scale > 1.0)
    }

    /// The size the (aspect-fit) image actually occupies on screen before scaling.
    private func fittedImageSize(in container: CGSize) -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else { return container }
        let fit = min(container.width / image.size.width, container.height / image.size.height)
        return CGSize(width: image.size.width * fit, height: image.size.height * fit)
    }

    private func constrainOffset(_ offset: CGSize, scale: CGFloat, geo: GeometryProxy) -> CGSize {
        guard scale > 1.0 else { return .zero }
        // Bound to the *actual* scaled photo, not the full screen, so you can't
        // drag the image off into the letterboxed dead-space.
        let fitted = fittedImageSize(in: geo.size)
        let maxOffsetX = max(0, (fitted.width * scale - geo.size.width) / 2)
        let maxOffsetY = max(0, (fitted.height * scale - geo.size.height) / 2)
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
                    // Override the ringer/silent switch so video audio always plays.
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    try? AVAudioSession.sharedInstance().setActive(true)

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

    /// First-launch ask: request the system permission and, if granted,
    /// switch the daily reminder on (its didSet persists and schedules).
    func promptInitialPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    self.isEnabled = true
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
                        .background(Theme.brandGradient)
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
    @AppStorage("shareWithFrame") private var shareWithFrame: Bool = true
    @AppStorage("showFloatingYear") private var showFloatingYear: Bool = true
    @AppStorage(mascotStorageKey) private var mascotRaw = MascotKind.foldy.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MascotPicker(selectedRaw: $mascotRaw)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Companion")
                } footer: {
                    Text("Pick the little friend who greets you each day.")
                }

                Section {
                    Toggle("Daily Reminder", isOn: $notificationManager.isEnabled)
                    
                    if notificationManager.isEnabled {
                        DatePicker(
                            "Time",
                            selection: $notificationManager.notificationTime,
                            displayedComponents: .hourAndMinute
                        )
                        
                        Picker("Minimum Photos", selection: $notificationManager.minimumPhotos) {
                            Text("1 photo").tag(1)
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
                    Toggle("Include Timefold Frame", isOn: $shareWithFrame)
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("When on, shared photos include a branded card with the date. Turn off to share the original photo only.")
                }

                Section {
                    Toggle("Floating Year", isOn: $showFloatingYear)
                } header: {
                    Text("Grid")
                } footer: {
                    Text("Show the year as a large overlay while scrolling through your memories.")
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

// MARK: - Daily Reveal

// MARK: - Mascot picker (Settings)

private struct MascotPicker: View {
    @Binding var selectedRaw: String

    var body: some View {
        // Three companions fit on every screen — no scroll, just centered.
        HStack(spacing: 12) {
            ForEach(MascotKind.allCases) { kind in
                    let isSelected = kind.rawValue == selectedRaw
                    VStack(spacing: 4) {
                        TimeSprite(mood: .happy, kind: kind)
                            .scaleEffect(0.42)
                            .frame(width: 80, height: 90)
                        Text(kind.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.primary : .secondary)
                        Text(kind.blurb)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .frame(width: 106)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? Theme.pink.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? Theme.pink : Color.clear, lineWidth: 2)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onTapGesture {
                        Haptics.tap(.light)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedRaw = kind.rawValue
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Daily Reveal — a little time sprite who greets you each day.

private enum SpriteMood: Equatable {
    case sleepy, happy, delighted
    static func forCount(_ n: Int) -> SpriteMood {
        if n >= 10 { return .delighted }
        if n >= 4 { return .happy }
        return .sleepy
    }
}

/// The three companions the user can choose between. Each shares the same
/// face/mood machinery but has a distinct silhouette, palette and topper.
enum MascotKind: String, CaseIterable, Identifiable {
    case foldy, luna, mochi
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .foldy: return "Foldy"
        case .luna:  return "Luna"
        case .mochi: return "Mochi"
        }
    }

    var blurb: String {
        switch self {
        case .foldy: return "the timekeeper"
        case .luna:  return "the dreamer"
        case .mochi: return "the kitty"
        }
    }
}

private let mascotStorageKey = "selectedMascot"

private struct DailyRevealView: View {
    let assets: [PHAsset]
    let date: Date
    let onComplete: () -> Void

    // Sequence beats
    @State private var showMeta = false
    @State private var showHeadline = false
    @State private var dealt = 0              // how many cards are on the table
    @State private var spriteUp = false
    @State private var showBubble = false
    @State private var showHint = false
    @State private var flungAway = false      // dismissal: cards fly off the top
    @State private var isDismissing = false

    @AppStorage(mascotStorageKey) private var mascotRaw = MascotKind.foldy.rawValue
    private var kind: MascotKind { MascotKind(rawValue: mascotRaw) ?? .foldy }

    private var count: Int { assets.count }
    private var mood: SpriteMood { SpriteMood.forCount(count) }

    private var fanAssets: [PHAsset] { Array(assets.prefix(5)) }

    private var metaString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE · MMMM d"
        return f.string(from: date).uppercased()
    }

    private var headlineString: String {
        count == 1 ? "1 memory" : "\(count) memories"
    }

    private var yearSpan: Int {
        Set(assets.compactMap { $0.creationDate }.map {
            Calendar.current.component(.year, from: $0)
        }).count
    }

    private var subtitleString: String {
        yearSpan > 1 ? "ACROSS \(yearSpan) YEARS" : "FROM THIS DAY"
    }

    /// A tiny bit of companion personality, stable for the whole day.
    private var bubbleText: String {
        let lines: [String]
        switch Theme.daypart() {
        case .sunrise: lines = ["good morning!", "rise and shine!", "morning, you!"]
        case .day:     lines = ["welcome back!", "hi again!", "there you are!"]
        case .dusk:    lines = ["good evening!", "hey, you made it!", "evening!"]
        case .night:   lines = ["up late? me too", "psst… look!", "night owl club"]
        }
        let seed = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        return lines[seed % lines.count]
    }

    private var ink: Color { Theme.skyInk(for: Date()) }
    private var inkSoft: Color { Theme.skyInkSoft(for: Date()) }

    /// Where each card rests in the fan — spread *across*, left to right,
    /// each card landing on top of the previous one (dealt across a table),
    /// following a gentle arc.
    private func slot(_ i: Int, of n: Int) -> (offset: CGSize, rotation: Double) {
        let t = Double(i) - Double(n - 1) / 2
        let jitter: [Double] = [-1.5, 1.0, -0.5, 1.5, -1.0]
        return (
            CGSize(width: t * 43, height: pow(abs(t), 1.6) * 9),
            t * 7 + jitter[i % jitter.count]
        )
    }

    var body: some View {
        ZStack {
            Theme.sky().ignoresSafeArea()
            SunGlow()

            VStack(spacing: 0) {
                // Date + count header
                VStack(spacing: 10) {
                    Text(metaString)
                        .metaLabel(12, color: inkSoft)
                        .opacity(showMeta ? 1 : 0)
                        .offset(y: showMeta ? 0 : -8)

                    Text(headlineString)
                        .font(.timefoldSerif(44))
                        .foregroundStyle(ink)
                        .opacity(showHeadline ? 1 : 0)
                        .scaleEffect(showHeadline ? 1 : 0.92)
                        .blur(radius: showHeadline ? 0 : 6)

                    Text(subtitleString)
                        .metaLabel(11, color: inkSoft.opacity(0.85))
                        .opacity(showHeadline ? 1 : 0)
                }
                .padding(.top, 96)

                Spacer()

                // The hand of memories, dealt one by one
                ZStack {
                    ForEach(Array(fanAssets.enumerated()), id: \.element.localIdentifier) { i, asset in
                        let n = fanAssets.count
                        let s = slot(i, of: n)
                        let onTable = i < dealt

                        RevealPolaroid(asset: asset)
                            .rotationEffect(.degrees(
                                flungAway ? s.rotation * 3 : (onTable ? s.rotation : 0)
                            ))
                            .offset(
                                x: onTable ? s.offset.width : 0,
                                y: flungAway
                                    ? s.offset.height - 720
                                    : (onTable ? s.offset.height : 240)
                            )
                            .scaleEffect(onTable ? 1 : 0.55)
                            .opacity(onTable ? 1 : 0)
                            .zIndex(Double(i)) // dealt across: each card lands on the last
                            .animation(
                                flungAway
                                    ? .easeIn(duration: 0.32).delay(Double(i) * 0.04)
                                    : .spring(response: 0.55, dampingFraction: 0.72),
                                value: flungAway
                            )
                            .animation(.spring(response: 0.55, dampingFraction: 0.72), value: dealt)
                    }
                }
                .frame(height: 280)

                Spacer()

                // The companion, peeking up from the bottom to greet you
                ZStack(alignment: .top) {
                    TimeSprite(mood: mood, kind: kind)
                        .scaleEffect(0.72, anchor: .bottom)
                        .offset(y: spriteUp && !flungAway ? 0 : 190)
                        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: spriteUp)
                        .animation(.easeIn(duration: 0.25), value: flungAway)

                    SpeechBubbleView(text: bubbleText)
                        .scaleEffect(showBubble && !flungAway ? 1 : 0, anchor: .bottom)
                        .offset(y: -46)
                        .animation(.spring(response: 0.38, dampingFraction: 0.6), value: showBubble)
                        .animation(.easeIn(duration: 0.18), value: flungAway)
                }
                .frame(height: 190)

                Text("tap to open")
                    .font(.timefoldRounded(13, weight: .medium))
                    .foregroundStyle(inkSoft.opacity(0.7))
                    .padding(.top, 12)
                    .padding(.bottom, 46)
                    .opacity(showHint && !flungAway ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { completeDismiss() }
        .task { await runSequence() }
    }

    private func runSequence() async {
        withAnimation(.easeOut(duration: 0.45)) { showMeta = true }
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showHeadline = true }
        try? await Task.sleep(nanoseconds: 280_000_000)

        for i in 0..<fanAssets.count {
            dealt = i + 1
            Haptics.tap(.light)
            try? await Task.sleep(nanoseconds: 110_000_000)
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        spriteUp = true
        Haptics.tap(.medium)
        try? await Task.sleep(nanoseconds: 380_000_000)
        showBubble = true
        Haptics.tap(.soft)
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        withAnimation(.easeIn(duration: 0.5)) { showHint = true }

        // Linger, then let the user in. Their moment — no rush.
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        completeDismiss()
    }

    private func completeDismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        Haptics.tap(.soft)
        // Cards fling off the top, companion ducks away, then the scene lifts.
        flungAway = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            onComplete()
        }
    }
}

/// One dealt memory in the reveal fan.
private struct RevealPolaroid: View {
    let asset: PHAsset
    @State private var image: UIImage?

    private var yearCaption: String {
        guard let d = asset.creationDate else { return "" }
        return String(Calendar.current.component(.year, from: d))
    }

    var body: some View {
        PolaroidFrame(caption: yearCaption, photoSize: 148) {
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.pink.opacity(0.15)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 400, height: 400),
            contentMode: .aspectFill,
            options: opts
        ) { img, _ in
            DispatchQueue.main.async { self.image = img }
        }
    }
}

// MARK: - The sprite

private struct TimeSprite: View {
    let mood: SpriteMood
    var kind: MascotKind = .foldy

    @State private var eyeOpen: CGFloat = 1
    @State private var bob: CGFloat = 0
    @State private var waveAngle: Double = 0
    @State private var twinkle = false

    private let bodySize: CGFloat = 150
    private let inkColor = Color(red: 0.20, green: 0.13, blue: 0.16)

    private var eyeHeight: CGFloat {
        switch mood { case .sleepy: return 11; case .happy: return 18; case .delighted: return 21 }
    }

    private let sparkleOffsets: [CGSize] = [
        CGSize(width: -86, height: -72),
        CGSize(width:  90, height: -54),
        CGSize(width: -98, height:  12),
        CGSize(width:  96, height:  32),
        CGSize(width:   0, height: -98),
    ]

    // MARK: per-mascot styling

    private var gradient: LinearGradient {
        let c: [Color]
        switch kind {
        case .foldy: c = [Theme.orange, Theme.pink]
        case .luna:  c = [Color(red: 0.74, green: 0.72, blue: 0.97), Color(red: 0.55, green: 0.53, blue: 0.86)]
        case .mochi: c = [Color(red: 0.62, green: 0.92, blue: 0.82), Color(red: 0.34, green: 0.78, blue: 0.74)]
        }
        return LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var accent: Color {
        switch kind {
        case .foldy: return Theme.pink
        case .luna:  return Color(red: 0.60, green: 0.55, blue: 0.95)
        case .mochi: return Color(red: 0.95, green: 0.55, blue: 0.60)
        }
    }

    // Distinct silhouettes per mascot.
    @ViewBuilder private var bodyBlob: some View {
        switch kind {
        case .foldy, .luna:
            Circle().fill(gradient).frame(width: bodySize, height: bodySize)
        case .mochi:
            RoundedRectangle(cornerRadius: bodySize * 0.40, style: .continuous)
                .fill(gradient).frame(width: bodySize, height: bodySize * 0.94)        // squishy
        }
    }

    @ViewBuilder private var topper: some View {
        switch kind {
        case .foldy: clockTopknot
        case .luna:  starTopper
        case .mochi: EmptyView()      // mochi wears ears instead
        }
    }

    var body: some View {
        ZStack {
            // Soft ground shadow
            Ellipse()
                .fill(Color.black.opacity(0.12))
                .frame(width: bodySize * 0.7, height: 18)
                .offset(y: bodySize * 0.62)
                .blur(radius: 6)

            // Sparkles when delighted
            if mood == .delighted {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: [14, 10, 12, 9, 11][i]))
                        .foregroundStyle(accent)
                        .offset(sparkleOffsets[i])
                        .opacity(twinkle ? 1 : 0.3)
                        .scaleEffect(twinkle ? 1 : 0.7)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(Double(i) * 0.12), value: twinkle)
                }
            }

            // The character
            ZStack {
                topper
                    .offset(y: -bodySize * 0.54)

                // Cat ears for mochi (behind the body so they tuck in)
                if kind == .mochi {
                    HStack(spacing: bodySize * 0.46) {
                        Triangle().fill(gradient).frame(width: 36, height: 30)
                        Triangle().fill(gradient).frame(width: 36, height: 30)
                    }
                    .offset(y: -bodySize * 0.48)
                }

                bodyBlob
                    .overlay(
                        Circle().fill(.white.opacity(0.18))
                            .frame(width: bodySize * 0.42, height: bodySize * 0.30)
                            .offset(x: -bodySize * 0.18, y: -bodySize * 0.20)
                            .blur(radius: 6)
                    )
                    .shadow(color: accent.opacity(0.4), radius: 18, y: 8)

                // Blush cheeks
                HStack(spacing: bodySize * 0.40) {
                    cheek; cheek
                }
                .offset(y: bodySize * 0.09)

                // Face
                VStack(spacing: bodySize * 0.07) {
                    HStack(spacing: bodySize * 0.16) { eye; eye }
                    mouth
                }
                .offset(y: -bodySize * 0.02)

                // Waving arm
                Capsule()
                    .fill(gradient)
                    .frame(width: 18, height: 40)
                    .rotationEffect(.degrees(waveAngle), anchor: .bottom)
                    .offset(x: bodySize * 0.5, y: 4)
                    .shadow(color: accent.opacity(0.3), radius: 6, y: 3)
            }
            // A quiet breathing squash — alive, but firmly on the ground.
            .scaleEffect(x: 1 + bob * 0.006, y: 1 - bob * 0.008, anchor: .bottom)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { bob = -4 }
            twinkle = true
        }
        .task { await animateLoop() }
    }

    private var cheek: some View {
        Ellipse().fill(accent.opacity(0.35)).frame(width: 20, height: 12)
    }

    private var eye: some View {
        ZStack {
            Capsule().fill(inkColor).frame(width: 15, height: eyeHeight)
            Circle().fill(.white).frame(width: 5, height: 5)
                .offset(x: 2.5, y: -eyeHeight * 0.22)
        }
        .scaleEffect(x: 1, y: eyeOpen, anchor: .center)
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .sleepy:
            SmileArc(curve: 0.45)
                .stroke(inkColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 24, height: 12)
        case .happy:
            SmileArc(curve: 0.85)
                .stroke(inkColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 30, height: 16)
        case .delighted:
            OpenSmile()
                .fill(inkColor)
                .frame(width: 30, height: 20)
        }
    }

    // MARK: toppers

    // Foldy — a little ticking clock, a nod to "Timefold."
    private var clockTopknot: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Theme.cream).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Theme.orange, lineWidth: 2))
                Capsule().fill(Theme.pink).frame(width: 2, height: 7).offset(y: -3)
                Capsule().fill(Theme.pink).frame(width: 2, height: 5)
                    .rotationEffect(.degrees(80)).offset(x: 2, y: 0)
            }
            Capsule().fill(Theme.orange).frame(width: 3, height: 12)
        }
    }

    // Luna — a star on a wand.
    private var starTopper: some View {
        VStack(spacing: 0) {
            Image(systemName: "star.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.cream)
                .shadow(color: .white.opacity(0.8), radius: 4)
            Capsule().fill(Color.white.opacity(0.85)).frame(width: 3, height: 9)
        }
    }

    private func animateLoop() async {
        // Wave hello a few times
        for _ in 0..<3 {
            withAnimation(.easeInOut(duration: 0.22)) { waveAngle = 24 }
            try? await Task.sleep(nanoseconds: 230_000_000)
            withAnimation(.easeInOut(duration: 0.22)) { waveAngle = -4 }
            try? await Task.sleep(nanoseconds: 230_000_000)
        }
        withAnimation(.easeInOut(duration: 0.3)) { waveAngle = 0 }

        // Idle blinking
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 2_200_000_000...4_200_000_000))
            withAnimation(.easeInOut(duration: 0.08)) { eyeOpen = 0.12 }
            try? await Task.sleep(nanoseconds: 110_000_000)
            withAnimation(.easeInOut(duration: 0.10)) { eyeOpen = 1 }
        }
    }
}

private struct SmileArc: Shape {
    var curve: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.width, y: 0),
                       control: CGPoint(x: rect.width / 2, y: rect.height * 2 * curve))
        return p
    }
}

private struct OpenSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0),
                       control: CGPoint(x: rect.width / 2, y: rect.height * 2))
        p.closeSubpath()
        return p
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Speech bubble

private struct SpeechBubbleView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.24))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                BubbleShape()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            )
    }
}

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bodyRect = CGRect(x: 0, y: 0, width: rect.width, height: max(0, rect.height - 8))
        let r = min(bodyRect.height / 2, 18)
        var p = Path(roundedRect: bodyRect, cornerRadius: r)
        let cx = rect.width / 2
        var tail = Path()
        tail.move(to: CGPoint(x: cx - 9, y: bodyRect.maxY - 2))
        tail.addLine(to: CGPoint(x: cx, y: rect.maxY))
        tail.addLine(to: CGPoint(x: cx + 9, y: bodyRect.maxY - 2))
        tail.closeSubpath()
        p.addPath(tail)
        return p
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

        let dateText = storyFormattedDate(asset.creationDate) as NSString
        let yearsText = storyYearsAgo(asset.creationDate) as NSString
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 72 * scale, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let yearsAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 54 * scale, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.9)
        ]
        let dateSize = dateText.size(withAttributes: dateAttrs)
        let yearsSize = yearsText.size(withAttributes: yearsAttrs)

        let maxPhotoWidth = 900 * scale
        let maxPhotoHeight = 1200 * scale
        let imageAspect = image.size.width / image.size.height
        let photoWidth: CGFloat
        let photoHeight: CGFloat
        if imageAspect > maxPhotoWidth / maxPhotoHeight {
            photoWidth = maxPhotoWidth
            photoHeight = maxPhotoWidth / imageAspect
        } else {
            photoHeight = maxPhotoHeight
            photoWidth = maxPhotoHeight * imageAspect
        }

        let textBlockHeight = 165 * scale + yearsSize.height
        let logoBottom = logoY + badgeHeight
        let availableHeight = canvasSize.height - logoBottom
        let photoY = logoBottom + max(50 * scale, (availableHeight - photoHeight - textBlockHeight) / 2)

        let photoRect = CGRect(x: (canvasSize.width - photoWidth) / 2, y: photoY, width: photoWidth, height: photoHeight)

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

        ctx.setShadow(offset: CGSize(width: 0, height: 4 * scale), blur: 12 * scale, color: UIColor.black.withAlphaComponent(0.3).cgColor)
        dateText.draw(at: CGPoint(x: (canvasSize.width - dateSize.width) / 2, y: photoRect.maxY + 75 * scale), withAttributes: dateAttrs)
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
    let calendar = Calendar.current
    let now = Date()
    let dateYear = calendar.component(.year, from: date)
    let nowYear = calendar.component(.year, from: now)
    let dateMonthDay = calendar.dateComponents([.month, .day], from: date)
    let nowMonthDay = calendar.dateComponents([.month, .day], from: now)
    var years = nowYear - dateYear
    if let dateMonth = dateMonthDay.month, let dateDay = dateMonthDay.day,
       let nowMonth = nowMonthDay.month, let nowDay = nowMonthDay.day {
        if nowMonth < dateMonth || (nowMonth == dateMonth && nowDay < dateDay) {
            years -= 1
        }
    }
    if years <= 0 { return "Today" }
    if years == 1 { return "1 year ago today" }
    return "\(years) years ago today"
}
