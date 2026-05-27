# MockFileServer

> A lightweight Swift Package that intercepts `URLSession` network calls during UI tests — returning mock JSON responses from local files, with zero real network traffic.

No localhost server. No third-party dependencies. Pure Apple APIs.

---

## Why MockFileServer?

UI tests that hit a real network are slow, flaky, and environment-dependent. MockFileServer solves this by plugging into `URLProtocol` — the same interception layer Apple itself uses — so your app code never changes, and your tests always get predictable, fast responses.

- ✅ Works with **GraphQL** (Apollo iOS, custom clients) and **REST**
- ✅ Supports **sequential responses** — simulate retry, pagination, or auth refresh in a single test
- ✅ **Plist-driven** test plans — swap scenarios without touching Swift code
- ✅ **No external dependencies** — 100% Foundation + URLSession
- ✅ Swift 6 / `Sendable`-safe

---

## How It Works

```
UI Test                    App                     MockFileServer
   │                        │                            │
   │── loadTestPlan() ──────►│                            │
   │                        │── URLSession.data(from:) ──►│
   │                        │                      intercepts via URLProtocol
   │                        │◄─ JSON from local file ────│
   │◄── assert response ────│                            │
```

`MockURLProtocol` registers itself with `URLSession` and intercepts every outgoing request. It resolves the request to an **operation name**, looks up the matching JSON file from `TestPlan.plist`, and returns the data directly — no network involved.

---

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies**, then enter:

```
https://github.com/livedz/MockFileServer
```

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/livedz/MockFileServer", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["MockFileServer"])
]
```

> **Important:** Add `MockFileServer` to your **app target** (not just the test target). The mock server runs inside the app process during UI tests.

---

## Setup (5 steps)

### 1. Add an AppDelegate

```swift
import UIKit
import MockFileServer

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if ProcessInfo.processInfo.environment["UI_TESTING"] == "1" {
            MockFileServer.shared.start()

            // REST projects: tell MockFileServer how your URLs map to operation names
            MockFileServer.shared.registerURLMapping { url in
                if url.path.contains("quotes")     { return "GetQuote" }
                if url.path.contains("characters") { return "GetCharacter" }
                return nil // fall through to last-path-component fallback
            }
        }
        return true
    }
}
```

```swift
// In your SwiftUI App entry point:
@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

### 2. Create `TestAction.plist`

Defines all operations and their available JSON file aliases. Add this to your **app target**.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>GetQuote</key>
    <dict>
        <key>success</key>       <string>quote_success</string>
        <key>empty</key>         <string>quote_empty</string>
    </dict>
    <key>GetCharacter</key>
    <dict>
        <key>success</key>       <string>character_walter</string>
        <key>notFound</key>      <string>character_not_found</string>
    </dict>
</dict>
</plist>
```

### 3. Create `TestPlan.plist`

Maps named test scenarios to which alias each operation should use.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <!-- Happy path: both operations succeed -->
    <key>QuoteSuccess</key>
    <dict>
        <key>GetQuote</key>      <dict><key>default</key><string>success</string></dict>
        <key>GetCharacter</key>  <dict><key>default</key><string>success</string></dict>
    </dict>

    <!-- Error path: quote fetch returns 500 -->
    <key>QuoteServerError</key>
    <dict>
        <key>GetQuote</key>
        <dict>
            <key>default</key>      <string>success</string>
            <key>status_code</key>  <integer>500</integer>
        </dict>
    </dict>
</dict>
</plist>
```

### 4. Add JSON files

Place your mock JSON responses in a `MockResources/Jsons/` folder inside the app target. MockFileServer searches these directories automatically:

```
YourApp/
└── MockResources/
    └── Jsons/
        ├── quote_success.json
        ├── quote_empty.json
        ├── character_walter.json
        └── character_not_found.json
```

### 5. Write UI tests

```swift
import XCTest

final class QuoteUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
    }

    func test_quoteScreen_showsQuote_onSuccess() {
        MockFileServer.shared.loadTestPlan("QuoteSuccess")
        app.launch()

        XCTAssertTrue(app.staticTexts["I am the one who knocks!"].waitForExistence(timeout: 3))
    }

    func test_quoteScreen_showsError_onServerFailure() {
        MockFileServer.shared.loadTestPlan("QuoteServerError")
        app.launch()

        XCTAssertTrue(app.staticTexts["Something went wrong"].waitForExistence(timeout: 3))
    }

    override func tearDown() {
        MockFileServer.shared.stop()
        super.tearDown()
    }
}
```

---

## Sequential Responses

Test retry logic, pagination, or auth token refresh by returning **different responses per call** to the same operation — using a linked list under the hood.

```xml
<!-- TestPlan.plist: Login fails first, succeeds on retry -->
<key>LoginWithRetry</key>
<dict>
    <key>Login</key>
    <dict>
        <key>default</key>      <string>loginFailed</string>
        <key>status_code</key>  <integer>401</integer>

        <!-- Nested same key = next node in the linked list -->
        <key>Login</key>
        <dict>
            <key>default</key>      <string>loginSuccess</string>
            <key>status_code</key>  <integer>200</integer>
        </dict>
    </dict>
</dict>
```

First call to `Login` → 401 `loginFailed.json`. Second call → 200 `loginSuccess.json`. Further calls replay the last node.

---

## Operation Name Resolution

`MockURLProtocol` resolves the operation name in this priority order:

| Priority | Source | Use case |
|:---:|---|---|
| 1 | `X-Apollo-Operation-Name` header | Apollo iOS GraphQL |
| 2 | `X-Operation-Name` header | Custom GraphQL clients |
| 3 | `operationName` field in request body | Generic GraphQL |
| 4 | App-registered URL mapping closure | REST APIs |
| 5 | Last path component of URL | REST fallback |

---

## API Reference

### `MockFileServer`

| Method / Property | Description |
|---|---|
| `MockFileServer.shared` | Singleton access |
| `start()` | Registers `MockURLProtocol` with `URLSession` |
| `stop()` | Unregisters and resets all loaded plans |
| `reset()` | Clears loaded plans without stopping |
| `loadTestPlan(_ name:, resourceBundle:)` | Loads a named scenario from `TestPlan.plist` |
| `registerURLMapping(_ mapper:)` | Registers a URL → operation name closure for REST |
| `resourceBundle` | Override to load plists/JSON from a custom bundle |
| `response(for operationName:)` | Returns the resolved `MockResponse` (called internally by `MockURLProtocol`) |

### `MockResponse`

```swift
public struct MockResponse {
    public let data: Data
    public let statusCode: Int      // default: 200
    public let headers: [String: String]
}
```

### Response Headers Added Automatically

Every mock response includes these debug headers:

| Header | Value |
|---|---|
| `X-Mock-Operation` | Operation name that was matched |
| `X-Mock-File` | JSON filename that was served |

---

## Project Structure

```
MockFileServer/
├── Sources/MockFileServer/
│   ├── MockFileServer.swift      # Core singleton — lifecycle, plan loading, response resolution
│   ├── MockURLProtocol.swift     # URLProtocol subclass — request interception + operation resolution
│   ├── MockNode.swift            # Generic linked list node for sequential responses
│   └── MockTypes.swift           # Enums: HTTP status codes, request methods, plist keys, errors
└── Tests/MockFileServerTests/
    ├── MockFileServerTests.swift  # Unit tests (Swift Testing framework)
    └── Resources/
        ├── TestAction.plist
        ├── TestPlan.plist
        └── quote_success.json
```

---

## Requirements

| | |
|---|---|
| **Swift** | 6.2+ |
| **Platforms** | iOS 13+, macOS 12+ |
| **Dependencies** | None — Foundation only |

---

## GraphQL (Apollo iOS) Example

For Apollo iOS projects, no URL mapping is needed. Apollo automatically sets `X-Apollo-Operation-Name` on every request, which MockFileServer reads directly.

```swift
// AppDelegate — no registerURLMapping needed for Apollo
if ProcessInfo.processInfo.environment["UI_TESTING"] == "1" {
    MockFileServer.shared.start()
    // That's it — Apollo headers are read automatically
}
```

---

