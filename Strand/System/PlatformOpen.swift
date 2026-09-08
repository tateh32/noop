import Foundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Tiny open / pasteboard helpers so Support and Shortcuts compile on iPhone and Mac.
enum PlatformOpen {
    static func url(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

/// User-facing “where this data lives” copy — iPhone vs Mac.
enum DeviceCopy {
    static var here: String {
        #if os(iOS)
        "this iPhone"
        #else
        "this Mac"
        #endif
    }
}
