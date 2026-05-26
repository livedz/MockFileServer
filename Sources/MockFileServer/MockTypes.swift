//
//  MockTypes.swift
//  MockFileServer
//
//  Created by MOKSHA on 21/05/26.
//

import Foundation

// MARK: - HTTP Status Codes

public enum MockHTTPStatus: Int {
    case ok           = 200
    case created      = 201
    case badRequest   = 400
    case unauthorized = 401
    case forbidden    = 403
    case notFound     = 404
    case notAcceptable = 406
    case tooManyRequests = 429
    case internalServerError = 500
}

// MARK: - Request Method

public enum MockRequestMethod: String {
    case GET, POST, PUT, PATCH, DELETE
}

// MARK: - Plist Keys

/// Keys used in TestAction.plist and TestPlan.plist
public enum MockPlistKey: String {
    case defaultFile  = "default"
    case statusCode   = "status_code"
    case httpMethod   = "http_method"
}

// MARK: - Response Header Keys

/// Headers added to every mock response so tests can inspect what was returned
public enum MockResponseHeader: String {
    case operationName = "X-Mock-Operation"
    case fileName      = "X-Mock-File"
}

// MARK: - MockResponse

/// The resolved response MockFileServer returns for any request
public struct MockResponse {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(
        data: Data,
        statusCode: Int = MockHTTPStatus.ok.rawValue,
        headers: [String: String] = [:]
    ) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

// MARK: - Errors

public enum MockFileServerError: Error, LocalizedError {
    case testPlanNotFound(String)
    case testActionNotFound
    case jsonFileNotFound(String)
    case operationNotRegistered(String)
    case invalidJSONData(String)

    public var errorDescription: String? {
        switch self {
        case .testPlanNotFound(let name):
            return "TestPlan '\(name)' not found in TestPlan.plist"
        case .testActionNotFound:
            return "TestAction.plist not found in app bundle"
        case .jsonFileNotFound(let name):
            return "JSON file '\(name).json' not found in app bundle"
        case .operationNotRegistered(let name):
            return "No mock registered for '\(name)'. Did you call loadTestPlan()?"
        case .invalidJSONData(let name):
            return "Invalid JSON data in '\(name).json'"
        }
    }
}
