//
//  TimefoldWidgetLiveActivity.swift
//  TimefoldWidget
//
//  Created by Ryan Curran on 1/29/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct TimefoldWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct TimefoldWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimefoldWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension TimefoldWidgetAttributes {
    fileprivate static var preview: TimefoldWidgetAttributes {
        TimefoldWidgetAttributes(name: "World")
    }
}

extension TimefoldWidgetAttributes.ContentState {
    fileprivate static var smiley: TimefoldWidgetAttributes.ContentState {
        TimefoldWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: TimefoldWidgetAttributes.ContentState {
         TimefoldWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: TimefoldWidgetAttributes.preview) {
   TimefoldWidgetLiveActivity()
} contentStates: {
    TimefoldWidgetAttributes.ContentState.smiley
    TimefoldWidgetAttributes.ContentState.starEyes
}
