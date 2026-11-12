import Foundation

/// Mints short-lived Simli session tokens. The API key is read from the Keychain here and sent only to
/// api.simli.ai; the web page receives the token, never the key.
enum SimliSession {
    static let account = "simli-api-key"
    /// Simli's Trinity-2 preset face from their docs; replace in Settings with any face ID from your account.
    static let defaultFaceID = "bf13113a-355a-4d97-8b90-4edccd1da7b2"

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func fetchToken(faceID: String) async throws -> String {
        guard let key = Keychain.get(account), !key.isEmpty else {
            throw Failure(errorDescription: "No Simli API key saved")
        }
        var request = URLRequest(url: URL(string: "https://api.simli.ai/compose/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-simli-api-key")
        request.timeoutInterval = 15
        // Sessions end after 2 minutes without audio so free-tier minutes aren't burned while Claude is quiet.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "faceId": faceID, "maxSessionLength": 3600, "maxIdleTime": 120,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw Failure(errorDescription: "Simli refused the request (HTTP \(status)\(detail.map { ": \($0)" } ?? "")). "
                          + (detail == "INVALID_API_KEY" ? "Check the API key." : "Check the API key and face ID."))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["session_token"] as? String else {
            throw Failure(errorDescription: "Unexpected response from Simli")
        }
        return token
    }
}
