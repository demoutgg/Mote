import Foundation

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let temperature: Double
}

private struct StreamChunk: Decodable {
    let choices: [StreamChoice]
}

private struct StreamChoice: Decodable {
    let delta: StreamDelta
}

private struct StreamDelta: Decodable {
    let content: String?
}

enum TranslationError: LocalizedError {
    case invalidEndpoint
    case httpStatus(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "API Endpoint 无效，请检查设置。"
        case let .httpStatus(status, body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "API 返回 HTTP \(status)\(trimmed.isEmpty ? "" : "：\(trimmed.prefix(500))")"
        case .emptyResponse:
            return "服务没有返回可用的流式内容。"
        }
    }
}

final class TranslationService {
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func stream(
        text: String,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard let url = Self.endpointURL(from: store.config.endpoint) else {
            throw TranslationError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let apiKey = store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let systemPrompt = store.config.systemPrompt
            .replacingOccurrences(of: "{targetLang}", with: store.config.targetLanguage)
        let body = ChatRequest(
            model: store.config.model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: text),
            ],
            stream: true,
            temperature: store.config.temperature
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count >= 4096 { break }
            }
            let errorBody = String(data: errorData, encoding: .utf8) ?? ""
            throw TranslationError.httpStatus(statusCode, errorBody)
        }

        var output = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let delta = chunk.choices.first?.delta.content else {
                continue
            }
            output += delta
            await onDelta(output)
        }

        guard !output.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return output
    }

    static func endpointURL(from rawValue: String) -> URL? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        if value.hasSuffix("/chat/completions") {
            // Already a full endpoint.
        } else if value.hasSuffix("/v1") {
            value += "/chat/completions"
        } else {
            value += "/v1/chat/completions"
        }
        return URL(string: value)
    }
}

