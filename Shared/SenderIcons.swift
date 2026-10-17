import Foundation
import UIKit

/// Sender website icons, downloaded once and kept in the App Group so the
/// app and the widget share them. A sender without an icon gets an empty
/// file, so it falls back to letters and is retried after a week.
///
/// Icons come from Google's favicon service, which therefore sees which
/// sender domains are looked up (never the emails themselves).
enum SenderIcons {
    nonisolated(unsafe) private static let memory = NSCache<NSString, UIImage>()

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.groupID)?
            .appending(path: "Library/Caches/SenderIcons", directoryHint: .isDirectory)
    }

    private static func file(_ domain: String) -> URL? {
        let safe = domain.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return safe.isEmpty ? nil : folder?.appending(path: safe + ".png")
    }

    static func image(for domain: String?) -> UIImage? {
        guard let domain, let url = file(domain) else { return nil }
        if let hit = memory.object(forKey: domain as NSString) { return hit }
        guard let data = try? Data(contentsOf: url), !data.isEmpty, let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: domain as NSString)
        return image
    }

    private static func needsFetch(_ domain: String) -> Bool {
        guard let url = file(domain) else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return true }
        if ((attrs[.size] as? NSNumber)?.intValue ?? 0) > 0 { return false }
        let checked = attrs[.modificationDate] as? Date ?? .distantPast
        return checked < Date.now.addingTimeInterval(-7 * 24 * 3600)
    }

    /// Downloads the icons that aren't cached yet (at most `limit` per call).
    static func prefetch(_ domains: [String], limit: Int = 30) async {
        let todo = Array(Set(domains.filter(needsFetch))).prefix(limit)
        guard !todo.isEmpty, let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await withTaskGroup(of: Void.self) { group in
            for domain in todo {
                group.addTask { await fetch(domain) }
            }
        }
    }

    private static func fetch(_ domain: String) async {
        guard let target = file(domain),
              let encoded = domain.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let source = URL(string: "https://www.google.com/s2/favicons?domain=\(encoded)&sz=128") else { return }
        var request = URLRequest(url: source)
        request.timeoutInterval = 10
        var keep = Data()
        if let result = try? await URLSession.shared.data(for: request),
           (result.1 as? HTTPURLResponse)?.statusCode == 200,
           let image = UIImage(data: result.0),
           image.size.width * image.scale >= 32 {
            keep = result.0
        }
        try? keep.write(to: target)
    }
}
