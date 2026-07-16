import Foundation

struct TranslatorConfig: Sendable {
    let baseURL: String
    let model: String
    let apiKey: String
    let targetLanguage: String
}

@MainActor
final class TranslatorClient {
    private let config: TranslatorConfig

    init(config: TranslatorConfig) {
        self.config = config
    }

    convenience init(settings: AppSettings) {
        self.init(config: TranslatorConfig(
            baseURL: settings.baseURL,
            model: settings.model,
            apiKey: settings.apiKey,
            targetLanguage: settings.targetLanguage
        ))
    }

    func translate(text: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        let baseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: baseURL),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            completion(.failure(TranslatorError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let prompt = """
        你是专业文档翻译助手。请把用户提供的文本翻译成\(config.targetLanguage)。
        要求：
        1. 只输出译文，不解释。
        2. 保留专有名词、缩写、金额、编号、URL 和代码片段。
        3. 对金融、合规、技术文档使用准确、正式、自然的表达。
        4. 如果原文已经是目标语言，请润色为清晰自然的目标语言文本。

        原文：
        \(text)
        """

        let body = ChatCompletionRequest(
            model: config.model,
            messages: [
                .init(role: "system", content: "You are a precise translation engine."),
                .init(role: "user", content: prompt)
            ]
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let message = Self.apiErrorMessage(data: data, statusCode: httpResponse.statusCode)
                completion(.failure(TranslatorError.api(message)))
                return
            }

            guard let data else {
                completion(.failure(TranslatorError.emptyResponse))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if let content, content.isEmpty == false {
                    completion(.success(content))
                } else {
                    completion(.failure(TranslatorError.emptyResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    nonisolated private static func apiErrorMessage(data: Data?, statusCode: Int) -> String {
        guard let data else { return "HTTP \(statusCode)" }

        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           let error = envelope.error {
            if let code = error.code, let message = error.message {
                return "\(code)：\(message)"
            }
            if let message = error.message {
                return message
            }
        }

        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           text.isEmpty == false {
            return text
        }
        return "HTTP \(statusCode)"
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody?

    struct APIErrorBody: Decodable {
        let code: String?
        let message: String?
    }
}

enum TranslatorError: LocalizedError {
    case invalidURL
    case emptyResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "API 地址无效。"
        case .emptyResponse:
            return "接口没有返回可用译文。"
        case .api(let message):
            return "接口错误：\(message)"
        }
    }
}
