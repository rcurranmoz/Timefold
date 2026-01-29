import Foundation
import Photos
import UIKit

class SharedMemoriesManager {
    static let shared = SharedMemoriesManager()
    
    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ryancurran.Timefold")
    }
    
    // Save today's memory count to a file (called from main app)
    func saveMemoryCount(_ count: Int) {
        guard let url = containerURL?.appendingPathComponent("todayCount.txt") else { return }
        try? String(count).write(to: url, atomically: true, encoding: .utf8)
    }
    
    // Read today's memory count from file (called from widget)
    func readMemoryCount() -> Int {
        guard let url = containerURL?.appendingPathComponent("todayCount.txt") else { return 0 }
        guard let countString = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return Int(countString) ?? 0
    }
}
