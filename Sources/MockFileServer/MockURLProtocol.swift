//
//  MockURLProtocol.swift
//  MockFileServer
//
//  Created by MOKSHA on 21/05/26.
//

import Foundation
/// Intercepts registered URLSession requests during UI tests.
/// Returns mock data from MockFileServer instead of hitting the real network.
/// The app tells the package how to map URLs to operation names
/// via MockFileServer.shared.registerURLMapping { url in ... }
public final class MockURLProtocol: URLProtocol {

    nonisolated(unsafe) static weak var server: MockFileServer?

    override public class func canInit(with request: URLRequest) -> Bool {
        guard let server = MockURLProtocol.server else { return false }

        if request.value(forHTTPHeaderField: "X-Apollo-Operation-Name") != nil {
            return true
        }

        if request.value(forHTTPHeaderField: "X-Operation-Name") != nil {
            return true
        }

        if let body = request.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           json["operationName"] as? String != nil {
            return true
        }

        guard let url = request.url else { return false }

        if server.urlMapper?(url) != nil {
            return true
        }

        return !url.lastPathComponent.isEmpty
            && url.lastPathComponent != "/"
            && server.hasOperation(named: url.lastPathComponent)
    }
    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        guard let server = MockURLProtocol.server else {
            client?.urlProtocol(
                self,
                didFailWithError: MockFileServerError.operationNotRegistered("MockFileServer not started")
            )
            return
        }

        let operationName = resolveOperationName(from: request, server: server)
        let mockResponse  = server.response(for: operationName)

        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "http://localhost")!,
            statusCode: mockResponse.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: mockResponse.headers
        )!

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mockResponse.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override public func stopLoading() {}

    // MARK: - Operation name resolution

    /// Resolves the operation name in this priority order:
    ///
    /// 1. GraphQL — X-Apollo-Operation-Name header (Apollo iOS)
    /// 2. GraphQL — X-Operation-Name header (generic)
    /// 3. GraphQL — operationName field in request body
    /// 4. REST    — app-registered URL mapping closure (your project's rules)
    /// 5. REST    — last path component of URL (generic fallback)
    /// 6. "unknown" if nothing matches
    private func resolveOperationName(from request: URLRequest, server: MockFileServer) -> String {

        // 1. Apollo GraphQL header
        if let name = request.value(forHTTPHeaderField: "X-Apollo-Operation-Name") {
            return name
        }

        // 2. Generic operation header
        if let name = request.value(forHTTPHeaderField: "X-Operation-Name") {
            return name
        }

        // 3. GraphQL body
        if let body = request.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let name = json["operationName"] as? String {
            return name
        }

        // 4. App-registered REST mapping — YOUR project defines this
        if let url = request.url,
           let name = server.urlMapper?(url) {
            return name
        }

        // 5. Generic REST fallback — last path component
        // e.g. https://api.example.com/v1/users → "users"
        if let url = request.url,
           !url.lastPathComponent.isEmpty,
           url.lastPathComponent != "/" {
            return url.lastPathComponent
        }

        return "unknown"
    }
}
