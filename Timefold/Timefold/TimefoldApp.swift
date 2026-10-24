//
//  TimefoldApp.swift
//  Timefold
//
//  Created by Ryan Curran on 1/20/26.
//

import SwiftUI
import UserNotifications

@main
struct TimefoldApp: App {
    init() {
        // Set before launch finishes, or a tap that cold-launched the app is
        // delivered to nobody.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if let link = DayLink(url: url) {
                        DeepLinkRouter.shared.pending = link
                    }
                }
        }
    }
}
