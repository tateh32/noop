import Foundation

/// Append-only BLE log next to whoop.sqlite so we can copy it off the phone
/// without a console. Caps at 256 KB by dropping the oldest half.
enum BLELogFile {
    private static let queue = DispatchQueue(label: "noop.ble.log")
    private static let maxBytes = 256 * 1024

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenWhoop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ble.log")
    }

    static func append(_ line: String) {
        queue.async {
            let stamped = line.hasSuffix("\n") ? line : line + "\n"
            guard let data = stamped.data(using: .utf8) else { return }
            let path = url
            if !FileManager.default.fileExists(atPath: path.path) {
                try? data.write(to: path)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: path) else { return }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                let size = try handle.offset()
                try handle.close()
                if size > maxBytes { trim(path) }
            } catch {
                try? handle.close()
            }
        }
    }

    private static func trim(_ path: URL) {
        guard let all = try? String(contentsOf: path, encoding: .utf8), all.count > 2 else { return }
        let keep = String(all.suffix(all.count / 2))
        try? keep.data(using: .utf8)?.write(to: path)
    }
}
