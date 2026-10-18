import Foundation
import ImageIO
import UIKit

/// Today's picture made for the widget (owner, 2026-10-18: the Home Screen widget showed a grey square).
///
/// WidgetKit refuses to archive a view whose image is much larger than the widget ("Widget archival
/// failed due to image being too large"; the limit is about 2.2 x 2 times the widget's own pixel size)
/// and the Home Screen then keeps the redacted placeholder: a grey square. Up to build 126 the picture
/// was shrunk with a UIGraphicsImageRenderer at the screen's scale (3x on an iPhone), which turned
/// "900 points" into 2,700 pixels: today's 1200 x 1508 picture came out 2149 x 2700, too large for every
/// widget size on an iPhone (the simulator's log said so for the medium size, totalArea 5802300 > max
/// 2644488).
///
/// Now ImageIO decodes the picture straight to about the widget's size (a large picture is never in
/// memory whole; a widget extension is stopped at about 30 MB), and it is drawn at scale 1 into exactly
/// the widget's pixels, filled and centred as the view shows it, with the fade under the title drawn in
/// (so it stays with the photo when the Home Screen tints widgets).
enum DailyPicture {
    /// The pixels the widget shows: its size in points times the screen's scale.
    struct Target: Equatable {
        let width: Int
        let height: Int

        init(width: Int, height: Int) {
            // Never empty, never past a size no iPhone widget has (an odd context must not undo the fix).
            self.width = min(max(width, 1), 1600)
            self.height = min(max(height, 1), 1600)
        }

        init(points: CGSize, scale: CGFloat) {
            let s = min(max(scale, 1), 3)
            self.init(width: Int((points.width * s).rounded(.up)), height: Int((points.height * s).rounded(.up)))
        }

        var size: CGSize { CGSize(width: width, height: height) }
    }

    /// The largest image WidgetKit archives for a widget of [target] pixels, as the archiver measured it
    /// (2.2 times the width by 2 times the height). The prepared picture is the target itself, well under.
    static func archiveLimit(for target: Target) -> Int {
        Int(Double(target.width) * 2.2 * Double(target.height) * 2.0)
    }

    /// The picture's size in pixels as it is shown (EXIF orientation applied), read from the file's header
    /// without decoding it.
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache as String: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue,
              w > 0, h > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    /// [data] (a JPEG or PNG) as exactly [target]'s pixels: scaled to fill, centred, with the title's
    /// fade drawn into the lower part. Nil when the data is not a picture.
    static func prepare(_ data: Data, for target: Target, fade: Bool = true) -> UIImage? {
        guard let full = pixelSize(of: data),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache as String: false] as CFDictionary) else { return nil }
        // Decode no larger than filling the target needs (never larger than the picture itself).
        let fill = max(CGFloat(target.width) / full.width, CGFloat(target.height) / full.height)
        let longSide = (max(full.width, full.height) * min(1, fill)).rounded(.up)
        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceShouldCacheImmediately as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: max(1, Int(longSide)),
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        // Pixels, not points: at the screen's scale (the default) the image would be 9 times the target.
        format.scale = 1
        format.opaque = true
        let size = target.size
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let w = CGFloat(decoded.width), h = CGFloat(decoded.height)
            let s = max(size.width / w, size.height / h)
            let rect = CGRect(x: (size.width - w * s) / 2, y: (size.height - h * s) / 2, width: w * s, height: h * s)
            UIImage(cgImage: decoded).draw(in: rect)
            guard fade else { return }
            // The fade the title sits on: clear at 35% of the height, 78% black at the bottom.
            let colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.78).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height * 0.35), end: CGPoint(x: 0, y: size.height), options: [.drawsAfterEndLocation])
            }
        }
    }

    /// The picture at about the widget's size from our own Storage: the `/preview` of a `/view` address
    /// (resized by Appwrite, 1080 wide like the pack covers), so a large original is never downloaded.
    /// Nil for an address that is not one of our Storage files; the widget then loads the address itself.
    static func previewURL(for view: String) -> URL? {
        guard var parts = URLComponents(string: view), parts.host == "fra.cloud.appwrite.io",
              parts.path.hasPrefix("/v1/storage/buckets/"), parts.path.hasSuffix("/view") else { return nil }
        parts.path = String(parts.path.dropLast("/view".count)) + "/preview"
        var items = (parts.queryItems ?? []).filter { !["width", "height", "quality", "output"].contains($0.name) }
        items += [URLQueryItem(name: "width", value: "1080"), URLQueryItem(name: "quality", value: "90")]
        parts.queryItems = items
        return parts.url
    }
}
