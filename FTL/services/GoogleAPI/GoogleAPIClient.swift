//
//  GoogleAPIClient.swift
//  google-api-test
//
//  Minimal authorized JSON client over URLSession, shared by the Gmail and
//  Sheets services. Attaches a fresh Bearer token to every request.
//

import Foundation

struct GoogleAPIClient {
    let auth: GoogleAuthManager

    /// Performs an authorized request and decodes the JSON response into `T`.
    func send<T: Decodable>(
        _ url: URL,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        let (data, _) = try await perform(url, method: method, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Performs an authorized request where the response body is not needed.
    @discardableResult
    func send(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> Data {
        try await perform(url, method: method, body: body).0
    }

    private func perform(_ url: URL, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        let token = try await auth.accessToken()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "<no body>"
            throw APIError.http(status: http.statusCode, body: message)
        }
        return (data, http)
    }

    enum APIError: LocalizedError {
        case invalidResponse
        case http(status: Int, body: String)
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid server response."
            case let .http(status, body):
                return "HTTP \(status): \(body)"
            case let .decoding(error):
                return "Failed to decode response: \(error.localizedDescription)"
            }
        }
    }
}
