// OpenAI 兼容的翻译请求：优先解析 SSE，服务端不支持流式时回退到完整 JSON；不做重试和缓存。
import CryptoKit
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

private struct ModelListResponse: Decodable {
    let data: [ModelEntry]?
}

private struct ModelEntry: Decodable {
    let id: String
}

private struct BaiduResponse: Decodable {
    let errorCode: String?
    let errorMsg: String?
    let transResult: [BaiduResult]?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMsg = "error_msg"
        case transResult = "trans_result"
    }
}

private struct BaiduResult: Decodable {
    let dst: String
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
            .replacingOccurrences(of: "{targetLang}", with: config.resolvedTargetLanguage(for: text))
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
            let errorData = try await Self.readBody(bytes, limit: 4096)
            throw TranslationError.httpStatus(
                httpResponse.statusCode,
                String(data: errorData, encoding: .utf8) ?? ""
            )
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

    func fetchModels(config: AppConfig, apiKey: String) async throws -> [String] {
        guard let url = Self.modelsURL(from: config.endpoint) else {
            throw TranslationError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse("")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TranslationError.httpStatus(
                httpResponse.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
        }

        do {
            let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
            let ids = (decoded.data ?? []).map(\.id).filter { !$0.isEmpty }.sorted()
            guard !ids.isEmpty else { throw TranslationError.emptyResponse }
            return ids
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
    }

    func translateBaidu(text: String, config: AppConfig, secret: String) async throws -> String {
        let appID = config.baiduAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty, !trimmedSecret.isEmpty else {
            throw TranslationError.invalidResponse("请先填写百度翻译的 AppID 和密钥。")
        }
        guard let url = URL(string: "https://fanyi-api.baidu.com/api/trans/vip/translate") else {
            throw TranslationError.invalidEndpoint
        }

        let salt = String(Int(Date().timeIntervalSince1970 * 1000))
        let sign = Self.md5(appID + text + salt + trimmedSecret)

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: "auto"),
            URLQueryItem(name: "to", value: config.baiduTargetCode(for: text)),
            URLQueryItem(name: "appid", value: appID),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse("")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TranslationError.httpStatus(
                httpResponse.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
        }

        let decoded: BaiduResponse
        do {
            decoded = try JSONDecoder().decode(BaiduResponse.self, from: data)
        } catch {
            throw TranslationError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }

        if let code = decoded.errorCode {
            throw TranslationError.invalidResponse(Self.baiduMessage(code, decoded.errorMsg))
        }

        let output = (decoded.transResult ?? [])
            .map(\.dst)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return output
    }

    private static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func baiduMessage(_ code: String, _ message: String?) -> String {
        switch code {
        case "52001":
            return "百度翻译请求超时，请重试。"
        case "52002":
            return "百度翻译系统错误，请重试。"
        case "52003":
            return "百度翻译未授权用户，请检查 AppID。"
        case "54000":
            return "百度翻译缺少必填参数。"
        case "54001":
            return "百度翻译签名错误，请检查密钥。"
        case "54003":
            return "百度翻译访问频率受限，请稍后再试。"
        case "54004":
            return "百度翻译账户余额不足。"
        case "54005":
            return "百度翻译长文本请求过于频繁，请稍后再试。"
        case "58000":
            return "百度翻译客户端 IP 非法。"
        case "58001":
            return "百度翻译不支持该语言方向。"
        case "58002":
            return "百度翻译服务已关闭。"
        case "90107":
            return "百度翻译认证未通过或尚未生效。"
        default:
            return message ?? "百度翻译返回错误 \(code)"
        }
    }

    static func modelsURL(from rawValue: String) -> URL? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        if value.hasSuffix("/chat/completions") {
            value.removeLast("/chat/completions".count)
        }
        if value.hasSuffix("/v1") {
            value += "/models"
        } else {
            value += "/v1/models"
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

    private static func readBody(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return data
    }
}

