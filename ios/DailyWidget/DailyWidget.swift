import WidgetKit
import SwiftUI

// Shows today's daily puzzle picture. The widget reads today's row from the public Appwrite catalogue
// (rows are world-readable) and the picture from our Appwrite Storage, and talks to nothing else (owner
// rule: the app talks only to Appwrite and Apple). There is no App Group: the app hands it nothing.
// The picture is prepared for the widget's exact pixels in DailyPicture.swift; why is written there.
struct DailyEntry: TimelineEntry {
    let date: Date
    let title: String
    let puzzleId: String
    let image: UIImage?
}

struct DailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyEntry {
        DailyEntry(date: Date(), title: "Today's puzzle", puzzleId: "", image: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyEntry) -> Void) {
        let target = DailyLoader.target(for: context)
        if context.isPreview {
            // The widget gallery: today's picture when the widget already has it, else the placeholder.
            completion(DailyLoader.cached(for: target) ?? placeholder(in: context))
            return
        }
        DailyLoader.load(for: target, done: completion)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        DailyLoader.load(for: DailyLoader.target(for: context)) { entry in
            let nextDay = DailyLoader.nextDayStart()
            // Without a picture (offline, a failed read) try again within the hour, never after the day changes.
            let refresh = entry.image == nil ? min(Date().addingTimeInterval(3600), nextDay) : nextDay
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
}

/// Reads today's row and picture. The last picture is kept in the widget's own caches folder, so a
/// failed read later the same day (and the widget gallery) still shows it.
enum DailyLoader {
    static let endpoint = "https://fra.cloud.appwrite.io/v1"
    static let project = "6acb4de5003e38d5ebd9"

    /// The widget's pixels: its size in points times the largest scale it is drawn at (3 when unknown,
    /// which on a 2x screen is still well under the archive limit).
    static func target(for context: TimelineProviderContext) -> DailyPicture.Target {
        let scale = context.environmentVariants.displayScale?.max() ?? 3
        return DailyPicture.Target(points: context.displaySize, scale: scale)
    }

    /// Today's daily puzzle id, `daily-YYYY-MM-DD` in the phone's own day (as the app shows it), with
    /// Gregorian digits whatever calendar and numbering system the phone uses.
    static func todayId(_ now: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return "daily-" + fmt.string(from: now)
    }

    /// A few minutes after the next local midnight, when the next daily picture is out.
    static func nextDayStart() -> Date {
        Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(6 * 3600)
    }

    static func load(for target: DailyPicture.Target, done: @escaping (DailyEntry) -> Void) {
        let id = todayId()
        var req = URLRequest(url: URL(string: "\(endpoint)/tablesdb/cjw/tables/puzzles/rows/\(id)")!, timeoutInterval: 20)
        req.setValue(project, forHTTPHeaderField: "X-Appwrite-Project")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let view = json["imageUrl"] as? String, !view.isEmpty else {
                done(cached(for: target, id: id) ?? DailyEntry(date: Date(), title: "Today's puzzle", puzzleId: id, image: nil))
                return
            }
            let title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Today's puzzle"
            // The resized preview first; the original from Storage when the preview cannot be had.
            let addresses = [DailyPicture.previewURL(for: view), URL(string: view)].compactMap { $0 }
            fetchPicture(addresses) { picture in
                if let picture, let image = DailyPicture.prepare(picture, for: target) {
                    store(picture, id: id, title: title)
                    done(DailyEntry(date: Date(), title: title, puzzleId: id, image: image))
                } else {
                    done(cached(for: target, id: id) ?? DailyEntry(date: Date(), title: title, puzzleId: id, image: nil))
                }
            }
        }.resume()
    }

    /// The first address that answers with a picture.
    private static func fetchPicture(_ addresses: [URL], done: @escaping (Data?) -> Void) {
        guard let url = addresses.first else { return done(nil) }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 20)) { data, response, _ in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200, DailyPicture.pixelSize(of: data) != nil {
                done(data)
            } else {
                fetchPicture(Array(addresses.dropFirst()), done: done)
            }
        }.resume()
    }

    // The last picture: <caches>/daily-widget.jpg and its row id and title beside it.
    private static var folder: URL? { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first }
    private static var pictureFile: URL? { folder?.appendingPathComponent("daily-widget.jpg") }
    private static var infoFile: URL? { folder?.appendingPathComponent("daily-widget.json") }

    private static func store(_ picture: Data, id: String, title: String) {
        guard let pictureFile, let infoFile, let info = try? JSONSerialization.data(withJSONObject: ["id": id, "title": title]) else { return }
        try? picture.write(to: pictureFile, options: .atomic)
        try? info.write(to: infoFile, options: .atomic)
    }

    /// Today's picture when it is the one kept ([id] nil: whichever day it is from, for the gallery).
    static func cached(for target: DailyPicture.Target, id: String? = nil) -> DailyEntry? {
        guard let pictureFile, let infoFile,
              let infoData = try? Data(contentsOf: infoFile),
              let info = try? JSONSerialization.jsonObject(with: infoData) as? [String: String],
              let keptId = info["id"], id == nil || keptId == id,
              let picture = try? Data(contentsOf: pictureFile),
              let image = DailyPicture.prepare(picture, for: target) else { return nil }
        return DailyEntry(date: Date(), title: info["title"] ?? "Today's puzzle", puzzleId: keptId, image: image)
    }
}

struct DailyWidgetView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetContentMargins) var margins
    let entry: DailyEntry

    private var titleSize: CGFloat {
        switch family {
        case .systemSmall: return 15
        case .systemMedium: return 18
        default: return 22
        }
    }

    private var titleLines: Int {
        family == .systemMedium ? 1 : 2
    }

    var body: some View {
        // The photo is content, not the container background: a Home Screen with tinted or clear icons
        // removes the background, and the picture went with it. Content margins are off for the photo to
        // reach the edges; the title keeps the standard margins.
        ZStack(alignment: .bottomLeading) {
            if let img = entry.image {
                // Already the widget's pixels, with the fade under the title drawn in.
                Image(uiImage: img)
                    .resizable()
                    .fullColorPhoto()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.75))
                Text(entry.title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(titleLines)
                    .minimumScaleFactor(0.85)
                if family != .systemSmall {
                    Text("Tap to play")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(margins)
        }
        .widgetURL(URL(string: "carden://play/\(entry.puzzleId)"))
        .containerBackground(for: .widget) {
            Color(red: 0.09, green: 0.09, blue: 0.11)
        }
    }
}

private extension Image {
    /// The photo keeps its colours when the Home Screen tints widgets (iOS 18 and later).
    @ViewBuilder func fullColorPhoto() -> some View {
        if #available(iOS 18.0, *) {
            self.widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}

@main
struct DailyWidget: Widget {
    let kind = "DailyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyProvider()) { entry in
            DailyWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily puzzle")
        .description("Today's picture, ready to play.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
