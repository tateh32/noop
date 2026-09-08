import Foundation

/// Copy a user-picked export into the app container before parsing.
///
/// iOS Files / iCloud / AirDrop URLs are security-scoped and often cannot be
/// read in place by ZIPFoundation (the zip central directory read fails, the
/// importer reports success-with-zero-rows or throws). macOS user-selected
/// files are more forgiving, but the same copy path is correct there too.
enum ImportStaging {
    enum StageError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let path):
                return "Couldn't open that file (\(path)). Pick the WHOOP .zip from Files or Downloads."
            }
        }
    }

    /// Security-scope the URL, coordinate a read, copy into a unique temp file, return that path.
    /// The copy itself is off the main actor — a WHOOP / Apple Health zip can be
    /// hundreds of MB, and `AppModel` is `@MainActor`.
    static func copyIntoInbox(_ url: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try copyNow(url)
        }.value
    }

    /// Synchronous copy. The detached worker and tests share this.
    static func copyNow(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var coordError: NSError?
        var copyError: NSError?
        var copied: URL?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { actual in
            let ext = actual.pathExtension.isEmpty ? "zip" : actual.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("noop-import-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: actual, to: dest)
                copied = dest
            } catch {
                copyError = error as NSError
            }
        }
        if let coordError { throw coordError }
        if let copyError { throw copyError }
        guard let copied, FileManager.default.fileExists(atPath: copied.path) else {
            throw StageError.unreadable(url.lastPathComponent)
        }
        return copied
    }
}
