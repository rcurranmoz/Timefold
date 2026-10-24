//
//  DeepLink.swift
//  Latent
//
//  One way in from outside the app: `latent://day/2026-10-22?year=2019`.
//  The widget, its per-year thumbnails and the daily notification all speak
//  it, so "tap the 2019 photo" always lands on the 2019 chapter of that day.
//

import Foundation
import UserNotifications
import Combine

/// A request to show a particular day, optionally scrolled to one year of it.
struct DayLink: Equatable {
    let date: Date
    let year: Int?

    static let scheme = "latent"

    /// `yyyy-MM-dd` in the user's calendar. Shared with the widget's forecast
    /// and the notification payload, so all three agree on what a day is.
    nonisolated static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(date: Date, year: Int? = nil) {
        self.date = date
        self.year = year
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == "day",
              let raw = url.pathComponents.dropFirst().first,
              let date = Self.dayFormatter.date(from: raw) else { return nil }
        self.date = date
        self.year = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "year" }?.value.flatMap(Int.init)
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["day"] as? String,
              let date = Self.dayFormatter.date(from: raw) else { return nil }
        self.date = date
        self.year = userInfo["year"] as? Int
    }

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = "day"
        c.path = "/" + Self.dayFormatter.string(from: date)
        if let year { c.queryItems = [URLQueryItem(name: "year", value: String(year))] }
        return c.url!
    }
}

/// Holds the most recent outside request until the main screen consumes it.
/// A notification tap can arrive before any view exists, so it cannot go
/// straight to one.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    @Published var pending: DayLink?
}

/// Routes notification taps into the router. Retained by the app for its
/// whole lifetime — `UNUserNotificationCenter.delegate` is weak.
///
/// Completion-handler forms, not the `async` ones, and the handler is always
/// called on the main thread. The async `didReceive` returns — and so calls
/// the system's completion handler — from whatever thread the task finished
/// on; UIKit then touches the scene off the main thread, and the app dies
/// the moment someone taps a notification (build 66/67, reported in
/// TestFlight).
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let link = DayLink(userInfo: userInfo) { DeepLinkRouter.shared.pending = link }
            }
            completionHandler()
        }
    }

    /// Arriving while Latent is already open: show it anyway, quietly.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async { completionHandler([.banner, .list]) }
    }
}

/// Testing hooks. `LATENT_DATE=yyyy-MM-dd` makes the app treat that day as
/// today — a simulator library rarely has photos on the real date. Always
/// nil in Release.
enum DebugOverrides {
    nonisolated static var forcedToday: Date? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["LATENT_DATE"] else { return nil }
        return DayLink.dayFormatter.date(from: raw)
        #else
        return nil
        #endif
    }
}
