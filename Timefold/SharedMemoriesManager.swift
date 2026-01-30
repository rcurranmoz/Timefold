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
    
    // Save a random photo thumbnail for widget (called from main app)
    func saveWidgetThumbnail(from asset: PHAsset) {
        guard let url = containerURL?.appendingPathComponent("widgetPhoto.jpg") else { return }
        
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat  // Better quality
        options.isSynchronous = true
        options.resizeMode = .exact  // Better sizing
        
        let targetSize = CGSize(width: 600, height: 600)  // Bigger for better quality
        
        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            guard let image = image,
                  let jpegData = image.jpegData(compressionQuality: 0.85) else { return }  // Higher quality
            try? jpegData.write(to: url)
        }
    }
    
    // Read widget thumbnail (called from widget)
    func readWidgetThumbnail() -> UIImage? {
        guard let url = containerURL?.appendingPathComponent("widgetPhoto.jpg") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
