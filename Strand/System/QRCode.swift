import Foundation
import CoreImage.CIFilterBuiltins
import CoreGraphics

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Generates a crisp QR code image for a string (e.g. a crypto address).
enum QRCode {
    private static let context = CIContext()

    static func cgImage(for string: String, scale: CGFloat = 12) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    #if os(macOS)
    static func image(for string: String, scale: CGFloat = 12) -> NSImage? {
        guard let cg = cgImage(for: string, scale: scale) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    #endif
}
