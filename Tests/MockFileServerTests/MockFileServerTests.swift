import Foundation
import Testing
@testable import MockFileServer

@Suite("MockFileServer Tests", .serialized)
struct MockFileServerTests {

    // MARK: - MockNode Tests

    @Test
    func node_returnsItself_whenNotCalled() async throws {
        let node = MockNode(value: "test")
        let result = node.nextUncalled()
        #expect(result.value == "test")
        #expect(result.isCalled == false)
    }

    @Test
    func node_returnsNext_whenCurrentCalled() async throws {
        let node1 = MockNode(value: "first")
        let node2 = MockNode(value: "second")
        node1.next = node2
        node1.isCalled = true

        let result = node1.nextUncalled()
        #expect(result.value == "second")
    }

    @Test
    func node_replaysLast_whenAllCalled() async throws {
        let node1 = MockNode(value: "first")
        let node2 = MockNode(value: "second")
        node1.next = node2
        node1.isCalled = true
        node2.isCalled = true

        let result = node1.nextUncalled()
        #expect(result.value == "second")
    }

    // MARK: - MockTypes Tests

    @Test
    func mockResponse_defaultStatusCode() async throws {
        let response = MockResponse(data: Data())
        #expect(response.statusCode == 200)
        #expect(response.headers.isEmpty)
    }

    @Test
    func mockResponse_customStatusCode() async throws {
        let response = MockResponse(data: Data(), statusCode: 401)
        #expect(response.statusCode == 401)
    }

    @Test
    func mockHTTPStatus_values() async throws {
        #expect(MockHTTPStatus.ok.rawValue == 200)
        #expect(MockHTTPStatus.unauthorized.rawValue == 401)
        #expect(MockHTTPStatus.notFound.rawValue == 404)
        #expect(MockHTTPStatus.internalServerError.rawValue == 500)
    }

    @Test
    func mockPlistKey_rawValues() async throws {
        #expect(MockPlistKey.defaultFile.rawValue == "default")
        #expect(MockPlistKey.statusCode.rawValue == "status_code")
        #expect(MockPlistKey.httpMethod.rawValue == "http_method")
    }

    @Test
    func mockResponseHeader_rawValues() async throws {
        #expect(MockResponseHeader.operationName.rawValue == "X-Mock-Operation")
        #expect(MockResponseHeader.fileName.rawValue == "X-Mock-File")
    }

    // MARK: - MockOperation Tests

    @Test
    func mockOperation_equality_basedOnName() async throws {
        let op1 = MockOperation(name: "GetQuote", fileMap: ["key": "value1"])
        let op2 = MockOperation(name: "GetQuote", fileMap: ["key": "value2"])
        #expect(op1 == op2) // same name = equal
    }

    @Test
    func mockOperation_inequality_differentNames() async throws {
        let op1 = MockOperation(name: "GetQuote", fileMap: [:])
        let op2 = MockOperation(name: "GetCharacter", fileMap: [:])
        #expect(op1 != op2)
    }

    // MARK: - Error description Tests

    @Test
    func error_testPlanNotFound_hasDescription() async throws {
        let error = MockFileServerError.testPlanNotFound("MyPlan")
        #expect(error.localizedDescription.contains("MyPlan"))
    }

    @Test
    func error_jsonFileNotFound_hasDescription() async throws {
        let error = MockFileServerError.jsonFileNotFound("quote_bb")
        #expect(error.localizedDescription.contains("quote_bb"))
    }

    @Test
    func error_operationNotRegistered_hasDescription() async throws {
        let error = MockFileServerError.operationNotRegistered("GetQuote")
        #expect(error.localizedDescription.contains("GetQuote"))
    }

    // MARK: - MockFileServer response Tests

    @Test
    func server_returnsErrorResponse_whenNoPlanLoaded() async throws {
        MockFileServer.shared.reset()
        let response = MockFileServer.shared.response(for: "GetQuote")
        #expect(response.statusCode == 404)

        let jsonAny = try? JSONSerialization.jsonObject(with: response.data)
        let json = jsonAny as? [String: Any]
        #expect(json != nil)
        #expect(json?["error"] != nil)
    }

    @Test
    func server_loadJSONFile_returnsNil_forMissingFile() async throws {
        let data = MockFileServer.shared.loadJSONFile(named: "non_existent_file")
        #expect(data == nil)
    }

    @Test
    func server_loadTestPlan_returnsFalse_whenPlistsAreMissing() async throws {
        MockFileServer.shared.resourceBundle = .main
        let didLoad = MockFileServer.shared.loadTestPlan("MissingPlan")
        #expect(didLoad == false)
    }

    @Test
    func server_loadTestPlan_loadsResources_fromProvidedBundle() async throws {
        let didLoad = MockFileServer.shared.loadTestPlan(
            "QuoteSuccess",
            resourceBundle: .module
        )
        #expect(didLoad == true)

        let response = MockFileServer.shared.response(for: "GetQuote")
        #expect(response.statusCode == 200)
        #expect(response.headers[MockResponseHeader.operationName.rawValue] == "GetQuote")
        #expect(response.headers[MockResponseHeader.fileName.rawValue] == "quote_success")

        let jsonAny = try JSONSerialization.jsonObject(with: response.data)
        let json = jsonAny as? [String: Any]
        #expect(json?["quote"] as? String == "Works from test resources")
    }

    @Test
    func server_startStop_canBeCalledRepeatedly() async throws {
        MockFileServer.shared.start()
        MockFileServer.shared.start()
        MockFileServer.shared.stop()
        MockFileServer.shared.stop()
    }
}
