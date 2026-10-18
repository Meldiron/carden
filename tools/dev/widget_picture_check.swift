// Checks the Home Screen widget's picture preparation (ios/DailyWidget/DailyPicture.swift) on an iOS
// simulator: every widget size of the iPhones the app supports gets a picture of exactly its pixels,
// well under WidgetKit's archive limit (the widget showed a grey square when it was not, owner
// 2026-10-18), from small, tall, wide, rotated and 4096 px pictures. Run by tools/dev/widget_picture_check.sh;
// with a JPEG path as the argument it also prepares that picture and writes the results as PNG files
// next to it for a look.
import Foundation
import ImageIO
import UIKit

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1 }
    print("\(ok ? "ok  " : "FAIL") \(what)")
}

/// A synthetic picture: colour bands, so a wrong crop or orientation would show in the PNGs.
func picture(_ w: Int, _ h: Int, orientation: Int = 1) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
        for i in 0..<8 {
            UIColor(hue: CGFloat(i) / 8, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: CGFloat(i) * CGFloat(h) / 8, width: CGFloat(w), height: CGFloat(h) / 8 + 1))
        }
    }
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image.cgImage!, [kCGImagePropertyOrientation as String: orientation, kCGImageDestinationLossyCompressionQuality as String: 0.85] as CFDictionary)
    CGImageDestinationFinalize(dest)
    return data as Data
}

// Widget sizes in points (systemSmall, systemMedium, systemLarge) and the screen scale.
let phones: [(String, [CGSize], CGFloat)] = [
    ("iPhone 17 Pro Max", [CGSize(width: 170, height: 170), CGSize(width: 378, height: 176.67), CGSize(width: 378, height: 394)], 3),
    ("iPhone 13 Pro", [CGSize(width: 158, height: 158), CGSize(width: 338, height: 158), CGSize(width: 338, height: 354)], 3),
    ("iPhone SE", [CGSize(width: 148, height: 148), CGSize(width: 321, height: 148), CGSize(width: 321, height: 324)], 2),
]
let pictures: [(String, Data)] = [
    ("today-like 1200x1508", picture(1200, 1508)),
    ("tall 1200x2134", picture(1200, 2134)),
    ("wide 2000x1000", picture(2000, 1000)),
    ("rotated (EXIF 6) 1500x1000", picture(1500, 1000, orientation: 6)),
    ("giant 4096x4096", picture(4096, 4096)),
    ("small 400x300", picture(400, 300)),
]

for (phone, sizes, scale) in phones {
    for points in sizes {
        let target = DailyPicture.Target(points: points, scale: scale)
        for (name, data) in pictures {
            let image = DailyPicture.prepare(data, for: target)
            let px = image.map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) } ?? .zero
            let area = Int(px.width * px.height)
            check(image != nil && Int(px.width) == target.width && Int(px.height) == target.height && area <= DailyPicture.archiveLimit(for: target),
                  "\(phone) \(Int(points.width))x\(Int(points.height))pt: \(name) -> \(Int(px.width))x\(Int(px.height)) px (limit \(DailyPicture.archiveLimit(for: target)) px)")
        }
    }
}

// The old way, for the record: a renderer at the screen's scale made a 1200 x 1508 picture 2149 x 2700 px.
let old = CGSize(width: 900 * 1200 / 1508.0, height: 900)
check(Int(old.width * 3 * old.height * 3) > DailyPicture.archiveLimit(for: DailyPicture.Target(points: CGSize(width: 338, height: 354), scale: 3)),
      "the old 900 pt picture at 3x (\(Int(old.width * 3))x\(Int(old.height * 3)) px) is over the largest iPhone 13 Pro widget's limit")

check(DailyPicture.prepare(Data("not a picture".utf8), for: DailyPicture.Target(width: 100, height: 100)) == nil, "data that is not a picture gives nil")
check(DailyPicture.pixelSize(of: picture(1500, 1000, orientation: 6)) == CGSize(width: 1000, height: 1500), "an EXIF-rotated picture reads as shown")

let view = "https://fra.cloud.appwrite.io/v1/storage/buckets/puzzle-images/files/p8d0d76116eb964768c9a16cf56f3a042f20/view?project=6acb4de5003e38d5ebd9"
check(DailyPicture.previewURL(for: view)?.absoluteString == "https://fra.cloud.appwrite.io/v1/storage/buckets/puzzle-images/files/p8d0d76116eb964768c9a16cf56f3a042f20/preview?project=6acb4de5003e38d5ebd9&width=1080&quality=90",
      "a Storage /view address becomes its /preview at 1080 px")
check(DailyPicture.previewURL(for: "https://upload.wikimedia.org/x.jpg") == nil, "an address that is not our Storage gets no preview")

// A real picture: prepared for every size of the first phone, written as PNG for a look.
if CommandLine.arguments.count > 1 {
    let path = CommandLine.arguments[1]
    if let data = FileManager.default.contents(atPath: path) {
        for (i, points) in phones[0].1.enumerated() {
            let target = DailyPicture.Target(points: points, scale: phones[0].2)
            if let image = DailyPicture.prepare(data, for: target), let png = image.pngData() {
                let out = (path as NSString).deletingPathExtension + "-widget-\(["small", "medium", "large"][i]).png"
                FileManager.default.createFile(atPath: out, contents: png)
                check(true, "\(path): \(target.width)x\(target.height) px -> \(out)")
            } else {
                check(false, "\(path) could not be prepared")
            }
        }
    } else {
        check(false, "cannot read \(path)")
    }
}

print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
