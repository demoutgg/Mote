// OpenAI 兼容的翻译请求：优先解析 SSE，服务端不支持流式时回退到完整 JSON；不做重试和缓存。
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

private struct APIErrorBody: Decodable {
    let message: String?
}

private struct StreamChunk: Decodable {
    let choices: [StreamChoice]?
    let error: APIErrorBody?
}

private struct StreamChoice: Decodable {
    let delta: StreamDelta?
}

private struct StreamDelta: Decodable {
    let content: String?
}

private struct ChatResponse: Decodable {
    let choices: [ResponseChoice]?
    let error: APIErrorBody?
}

private struct ResponseChoice: Decodable {
    let message: ResponseMessage?
}

private struct ResponseMessage: Decodable {
    let content: String?
}

enum TranslationError: LocalizedError {
    case invalidEndpoint
    case invalidResponse(String)
    case httpStatus(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "API Endpoint 无效，请填写 http(s) 地址。"
        case let .invalidResponse(body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "无法解析服务返回的内容\(trimmed.isEmpty ? "" : "：\(trimmed.prefix(300))")"
        case let .httpStatus(status, body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "API 返回 HTTP \(status)\(trimmed.isEmpty ? "" : "：\(trimmed.prefix(500))")"
        case .emptyResponse:
            return "服务没有返回翻译内容。"
        }
    }
}

final class TranslationService {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }

    func translate(
        text: String,
        config: AppConfig,
        apiKey: String,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard let url = Self.endpointURL(from: config.endpoint) else {
            throw TranslationError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let systemPrompt = config.systemPrompt
            .replacingOccurrences(of: "{targetLang}", with: config.targetLanguage)
        let body = ChatRequest(
            model: config.model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: text),
            ],
            stream: true,
            temperature: config.temperature
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse("")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = try await Self.readBody(bytes, limit: 4096)
            throw TranslationError.httpStatus(httpResponse.statusCode, errorBody)
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("text/event-stream") {
            return try await Self.consumeStream(bytes, onDelta: onDelta)
        }

        let rawBody = try await Self.readBody(bytes, limit: 2_000_000)
        return try await Self.consumeFullResponse(rawBody, onDelta: onDelta)
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

        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private static func consumeStream(
        _ bytes: URLSession.AsyncBytes,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        var output = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }

            if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {
                if let message = chunk.error?.message {
                    throw TranslationError.invalidResponse(message)
                }
                if let delta = chunk.choices?.first?.delta?.content {
                    output += delta
                    await onDelta(output)
                }
            }
        }

        guard !output.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return output
    }

    private static func consumeFullResponse(
        _ data: Data,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw TranslationError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }

        if let message = decoded.error?.message {
            throw TranslationError.invalidResponse(message)
        }
        guard let content = decoded.choices?.first?.message?.content, !content.isEmpty else {
            throw TranslationError.emptyResponse
        }

        await onDelta(content)
        return content
    }

    private static func readBody(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

