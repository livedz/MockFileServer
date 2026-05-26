
import Foundation

/// MockFileServer — pure Apple mock server using URLProtocol.
/// Instead of a real HTTP server on localhost:9080,
/// MockURLProtocol intercepts URLSession calls directly.
///
/// Setup in your project:
/// 1. Add MockFileServer package to your app
/// 2. Add AppDelegate with @UIApplicationDelegateAdaptor
/// 3. In AppDelegate: check ProcessInfo for UI test flag, call MockFileServer.shared.start()
/// 4. Add TestAction.plist, TestPlan.plist and Jsons/ folder to your app target
/// 5. In UI tests: set environment variable, then call loadTestPlan()
///
/// JSON files live in the APP bundle — not in this package.
/// This makes the package reusable across any project.
public final class MockFileServer: @unchecked Sendable {

    public static let shared = MockFileServer()

    // Linked list nodes — one per operation, same as SMUMockServer
    private var nodes: [MockNode<MockOperation>] = []
    private let lifecycleLock = NSLock()
    private var isStarted = false

    // The bundle that owns TestAction.plist, TestPlan.plist and JSON files
    // Default: Bundle.main (your app)
    // Override in tests if needed: MockFileServer.shared.resourceBundle = Bundle(for: MyTests.self)
    public var resourceBundle: Bundle = .main

    /// REST URL → operation name mapping closure.
    /// Register this in AppDelegate or test setUp() to tell MockFileServer
    /// how your project's REST URLs map to operation names.
    ///
    /// Example for another project:
    ///   MockFileServer.shared.registerURLMapping { url in
    ///       if url.path.contains("users")   { return "GetUsers" }
    ///       if url.path.contains("orders")  { return "GetOrders" }
    ///       return nil
    ///   }
    ///
    /// Return nil to fall through to the generic last-path-component fallback.
    public var urlMapper: ((URL) -> String?)? = nil

    public func registerURLMapping(_ mapper: @escaping (URL) -> String?) {
        self.urlMapper = mapper
    }

    func hasOperation(named operationName: String) -> Bool {
        nodes.contains { $0.value.name == operationName }
    }

    private init() {}

    // MARK: - Lifecycle

    /// Start the mock server.
    /// Call in AppDelegate when running UI tests.
    /// Registers MockURLProtocol with URLSession — all network calls intercepted from this point.
    public func start() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard !isStarted else { return }
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.server = self
        isStarted = true
    }

    /// Stop the mock server.
    /// Call in UI test tearDown().
    public func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard isStarted else {
            reset()
            return
        }
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.server = nil
        isStarted = false
        reset()
    }

    /// Reset all loaded plans — useful between tests.
    public func reset() {
        nodes = []
    }

    // MARK: - TestPlan loading

    /// Load a named test plan from TestPlan.plist in the app bundle.
    /// This wires each operation to its JSON file for this specific test scenario.
    ///
    /// Example:
    ///   MockFileServer.shared.loadTestPlan("BBQuoteSuccess")
    ///   // Now GetQuote → quote_bb.json, GetCharacter → character_walter.json
    @discardableResult
    public func loadTestPlan(_ planName: String, resourceBundle: Bundle? = nil) -> Bool {
        nodes = []
        if let resourceBundle {
            self.resourceBundle = resourceBundle
        }

        guard let actionMap = loadPlist(named: "TestAction") else {
            return false
        }

        guard let planMap = loadPlist(named: "TestPlan"),
              let plan = planMap[planName] as? [String: Any] else {
            return false
        }

        // Step 1: Build base nodes from TestAction — one node per operation
        var freshNodes: [MockNode<MockOperation>] = []
        for (operationName, value) in actionMap {
            let fileMap = value as? [String: Any] ?? [:]
            let op = MockOperation(name: operationName, fileMap: fileMap)
            freshNodes.append(MockNode(value: op))
        }

        // Step 2: Apply test plan overrides
        // For each operation in the plan, update which JSON file to serve
        // and build a linked list for sequential responses
        for (operationName, planValue) in plan {
            guard
                let planDict   = planValue as? [String: Any],
                let node       = freshNodes.first(where: { $0.value.name == operationName }),
                let actionDict = actionMap[operationName] as? [String: Any]
            else { continue }

            // Resolve which JSON file to use for this plan
            let resolvedFile = resolveFileName(planDict: planDict, actionDict: actionDict)
            node.value.fileMap[MockPlistKey.defaultFile.rawValue] = resolvedFile

            // Override status code if plan specifies one
            if let statusCode = planDict[MockPlistKey.statusCode.rawValue] as? Int {
                node.value.fileMap[MockPlistKey.statusCode.rawValue] = statusCode
            }

            // Build linked list for sequential responses
            node.next = buildLinkedList(
                operationName: operationName,
                planDict: planDict,
                actionDict: actionDict
            )
        }

        self.nodes = freshNodes
        return true
    }

    // MARK: - Response resolution

    /// Called by MockURLProtocol for every intercepted request.
    /// Returns the correct MockResponse based on loaded TestPlan.
    public func response(for operationName: String) -> MockResponse {
        guard let headNode = nodes.first(where: { $0.value.name == operationName }) else {
            return makeErrorResponse(
                MockFileServerError.operationNotRegistered(operationName).localizedDescription
            )
        }

        // Walk linked list — get next uncalled node
        let node = headNode.nextUncalled()
        node.isCalled = true

        // Get the JSON file name
        guard let fileName = node.value.fileMap[MockPlistKey.defaultFile.rawValue] as? String else {
            return makeErrorResponse("No default file for operation: \(operationName)")
        }

        // Load the JSON file from app bundle
        guard let data = loadJSONFile(named: fileName) else {
            return makeErrorResponse(
                MockFileServerError.jsonFileNotFound(fileName).localizedDescription
            )
        }

        let statusCode = node.value.fileMap[MockPlistKey.statusCode.rawValue] as? Int
            ?? MockHTTPStatus.ok.rawValue

        return MockResponse(
            data: data,
            statusCode: statusCode,
            headers: [
                MockResponseHeader.operationName.rawValue: operationName,
                MockResponseHeader.fileName.rawValue: fileName
            ]
        )
    }

    // MARK: - Private helpers

    /// Resolves which JSON file to use from a plan entry.
    /// TestPlan uses alias keys that map to real filenames in TestAction.
    ///
    /// Example:
    ///   TestAction: Login → { "loginSuccess": "login_success", "loginFailed": "login_failed" }
    ///   TestPlan:   Login → { "default": "loginSuccess" }
    ///   Result:     "login_success"
    private func resolveFileName(planDict: [String: Any], actionDict: [String: Any]) -> String {
        let aliasKey = planDict[MockPlistKey.defaultFile.rawValue] as? String ?? ""
        return actionDict[aliasKey] as? String ?? aliasKey
    }

    /// Recursively builds a linked list for sequential responses.
    /// Nested dictionary with the same key = next node in the list.
    private func buildLinkedList(
        operationName: String,
        planDict: [String: Any],
        actionDict: [String: Any]
    ) -> MockNode<MockOperation>? {
        guard let nested = planDict[operationName] as? [String: Any] else { return nil }

        let resolvedFile = resolveFileName(planDict: nested, actionDict: actionDict)
        var fileMap = nested.filter { $0.key != operationName }
        fileMap[MockPlistKey.defaultFile.rawValue] = resolvedFile

        if let statusCode = nested[MockPlistKey.statusCode.rawValue] as? Int {
            fileMap[MockPlistKey.statusCode.rawValue] = statusCode
        }

        let node = MockNode(value: MockOperation(name: operationName, fileMap: fileMap))
        node.next = buildLinkedList(
            operationName: operationName,
            planDict: nested,
            actionDict: actionDict
        )
        return node
    }

    /// Load a plist from the resource bundle
    private func loadPlist(named name: String) -> [String: Any]? {
        guard let url = resourceURL(named: name, extension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return nil
        }
        return dict
    }

    /// Load a JSON file from the resource bundle
    public func loadJSONFile(named fileName: String) -> Data? {
        guard let url = resourceURL(named: fileName, extension: "json") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func resourceURL(named name: String, extension fileExtension: String) -> URL? {
        let searchDirectories: [String?] = [
            nil,
            "MockResources",
            "MockResources/Jsons",
            "Jsons"
        ]

        for directory in searchDirectories {
            if let url = resourceBundle.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: directory
            ) {
                return url
            }
        }

        return nil
    }

    /// Build an error response for unhandled operations
    private func makeErrorResponse(_ message: String) -> MockResponse {
        let body = ["error": message, "mock": true] as [String: Any]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return MockResponse(data: data, statusCode: MockHTTPStatus.notFound.rawValue)
    }
}
