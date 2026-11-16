import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one thing the network clients need: send a request, get the body and the status code.
/// Tests supply their own so nothing touches the network.
public protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

public struct HTTPError: Error, LocalizedError, Equatable {
    public var status: Int
    public var message: String

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(timeout: TimeInterval = 45) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }
}

/// Reading loosely typed JSON without crashing on a missing or renamed field.
enum JSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? Double { return Int(n) }
        if let s = value as? String {
            if let n = Int(s.trimmingCharacters(in: .whitespaces)) { return n }
            if let d = Double(s.trimmingCharacters(in: .whitespaces)) { return Int(d) }
        }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? Int { return String(n) }
        if let n = value as? Double { return String(n) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let s = value as? String { return s.lowercased() == "true" }
        return nil
    }
}
