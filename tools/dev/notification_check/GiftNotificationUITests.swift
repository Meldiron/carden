import XCTest

/// Friend gift notification on the simulator, the parts Flutter cannot drive: the iOS permission
/// prompt, the banner while the game is in the background and the tap on it, on a real push from
/// Apple's sandbox service. Run by tools/dev/notification_check.sh, which adds this file to a
/// temporary UI test target (never committed to the Xcode project) and gives the QA guest a QA
/// friend. Env (TEST_RUNNER_ prefix on xcodebuild): GIFT_QA_DIR (screenshots), GIFT_QA_STATE
/// (secrets/gift_qa.json: the friend's session, written once the friend exists).
final class GiftNotificationUITests: XCTestCase {
  private let env = ProcessInfo.processInfo.environment
  private lazy var dir = env["GIFT_QA_DIR"] ?? NSTemporaryDirectory()
  private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

  private func shot(_ name: String) {
    let png = XCUIScreen.main.screenshot().pngRepresentation
    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func element(_ app: XCUIApplication, label: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
  }

  /// The friend sends the player a gift through the real function, with the friend's session.
  private func sendGift(kind: String) throws -> String {
    let path = try XCTUnwrap(env["GIFT_QA_STATE"])
    let state = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
    var req = URLRequest(url: URL(string: "https://fra.cloud.appwrite.io/v1/functions/api/executions")!)
    req.httpMethod = "POST"
    req.setValue("6acb4de5003e38d5ebd9", forHTTPHeaderField: "X-Appwrite-Project")
    req.setValue(state["secret"] as? String, forHTTPHeaderField: "X-Appwrite-Session")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body = try JSONSerialization.data(withJSONObject: ["friendId": state["playerId"]!, "kind": kind, "utcOffset": 120])
    req.httpBody = try JSONSerialization.data(withJSONObject: ["path": "/gift/send", "method": "POST", "body": String(data: body, encoding: .utf8)!, "async": false])
    let done = expectation(description: "gift/send")
    var answer = ""
    URLSession.shared.dataTask(with: req) { data, _, error in
      answer = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\(String(describing: error))"
      done.fulfill()
    }.resume()
    wait(for: [done], timeout: 60)
    return answer
  }

  /// Waits for the host to write the friend's state file: the host sees the guest this launch made
  /// and gives it a QA friend (`gift_qa.py befriend-run`).
  private func waitForFriend(seconds: Int) throws {
    let path = try XCTUnwrap(env["GIFT_QA_STATE"])
    var waited = 0
    while !FileManager.default.fileExists(atPath: path) && waited < seconds {
      sleep(1)
      waited += 1
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: path), "the host made a QA friend")
    sleep(2)
  }

  func testGiftNotification() throws {
    let app = XCUIApplication()
    app.launch()
    sleep(8)

    // Settings > Gifts from friends: the switch asks iOS.
    app.open(URL(string: "carden://settings")!)
    sleep(5)
    shot("gift_10_settings")
    // Flutter reads the whole Notifications group as one element. With the reminders off its
    // switches are, top to bottom: Daily reminders, New events, Gifts from friends, Messages from
    // Carden (docs/notifications.md), so Gifts from friends is the third.
    let group = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Gifts from friends'")).firstMatch
    XCTAssertTrue(group.waitForExistence(timeout: 10), "the Gifts from friends row")
    let switches = app.switches.allElementsBoundByIndex
      .filter { $0.frame.height > 0 && group.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
      .sorted { $0.frame.midY < $1.frame.midY }
    XCTAssertEqual(switches.count, 4, "the four notification switches")
    try XCTUnwrap(switches.count == 4 ? switches[2] : nil, "the Gifts from friends switch").tap()

    // iOS's own prompt.
    let allow = springboard.alerts.firstMatch.buttons["Allow"]
    XCTAssertTrue(allow.waitForExistence(timeout: 15), "the iOS notification prompt")
    shot("gift_11_ios_prompt")
    allow.tap()
    sleep(8) // the token reaches Appwrite as a push target
    shot("gift_12_settings_on")

    // The game goes to the background; a friend sends a ticket; the banner shows.
    XCUIDevice.shared.press(.home)
    sleep(2)
    try waitForFriend(seconds: 240)
    let sent = try sendGift(kind: "tickets")
    print("GIFT_QA_SENT \(sent)")
    let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'sent you a gift'")).firstMatch
    XCTAssertTrue(banner.waitForExistence(timeout: 90), "the gift notification banner")
    shot("gift_13_banner")

    // Its tap opens that message in the game; Claim adds the ticket.
    banner.tap()
    sleep(8)
    shot("gift_14_opened")
    let claim = element(app, label: "Claim")
    XCTAssertTrue(claim.waitForExistence(timeout: 15), "the message with its Claim button")
    claim.tap()
    sleep(4)
    shot("gift_15_claimed")
  }
}
