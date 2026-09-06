import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AIProvider: String, CaseIterable, Codable {
    case ollama
    case openai
    case anthropic
    case gemini
    case groq
    case openrouter
    case custom

    public var defaultBaseURL: String {
        switch self {
        case .ollama:
            return "http://localhost:11434/v1/chat/completions"
        case .openai:
            return "https://api.openai.com/v1/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .groq:
            return "https://api.groq.com/openai/v1/chat/completions"
        case .openrouter:
            return "https://openrouter.ai/api/v1/chat/completions"
        case .custom:
            return ""
        }
    }

    public var defaultModel: String {
        switch self {
        case .ollama:
            return "llama3.2"
        case .openai:
            return "gpt-4o-mini"
        case .anthropic:
            return "claude-3-5-sonnet-20241022"
        case .gemini:
            return "gemini-2.5-flash"
        case .groq:
            return "llama-3.3-70b-versatile"
        case .openrouter:
            return "anthropic/claude-3.5-sonnet"
        case .custom:
            return ""
        }
    }

    public var apiKeyEnvironmentVariable: String? {
        switch self {
        case .ollama:
            return nil
        case .openai:
            return "OPENAI_API_KEY"
        case .anthropic:
            return "ANTHROPIC_API_KEY"
        case .gemini:
            return "GEMINI_API_KEY"
        case .groq:
            return "GROQ_API_KEY"
        case .openrouter:
            return "OPENROUTER_API_KEY"
        case .custom:
            return nil
        }
    }
}

public struct AIEnhancementConfiguration: Equatable {
    public var provider: AIProvider
    public var model: String
    public var baseURL: String
    public var apiKey: String?
    public var systemPrompt: String
    public var temperature: Double

    public static let defaultSystemPrompt = """
    You are an expert voice dictation assistant. Your task is to clean up, format, and enhance raw speech-to-text transcriptions.
    Rules:
    1. Fix punctuation, capitalization, spelling, and grammar.
    2. Remove verbal disfluencies (ums, uhs, repeated words) while preserving the speaker's exact meaning and voice.
    3. Format lists, bullet points, code blocks, or paragraphs appropriately when dictated.
    4. Output ONLY the polished text. Do not add conversational prefixes, explanations, or commentary.
    """

    public init(
        provider: AIProvider = .ollama,
        model: String? = nil,
        baseURL: String? = nil,
        apiKey: String? = nil,
        systemPrompt: String = defaultSystemPrompt,
        temperature: Double = 0.3
    ) {
        self.provider = provider
        self.model = model ?? provider.defaultModel
        self.baseURL = baseURL ?? provider.defaultBaseURL
        self.apiKey = apiKey ?? (provider.apiKeyEnvironmentVariable.flatMap { ProcessInfo.processInfo.environment[$0] })
        self.systemPrompt = systemPrompt
        self.temperature = temperature
    }
}

public enum AIEnhancementError: Error, CustomStringConvertible {
    case invalidURL(String)
    case missingAPIKey(AIProvider)
    case requestFailed(String)
    case httpError(statusCode: Int, body: String)
    case invalidResponse(String)

    public var description: String {
        switch self {
        case .invalidURL(let url):
            return "invalid AI endpoint URL: '\(url)'"
        case .missingAPIKey(let provider):
            let envVar = provider.apiKeyEnvironmentVariable ?? "API key"
            return "missing API key for \(provider.rawValue). Pass --ai-api-key or set environment variable \(envVar)."
        case .requestFailed(let msg):
            return "AI enhancement network request failed: \(msg)"
        case .httpError(let code, let body):
            return "AI enhancement HTTP error \(code): \(body)"
        case .invalidResponse(let msg):
            return "invalid AI enhancement response: \(msg)"
        }
    }
}

extension URLSession {
    func executeDataTask(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, let response = response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.unknown))
                }
            }
            task.resume()
        }
    }
}

public enum AIEnhancementService {
    public static func enhance(
        text: String,
        config: AIEnhancementConfiguration = AIEnhancementConfiguration(),
        session: URLSession = .shared
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return text
        }

        guard let url = URL(string: config.baseURL) else {
            throw AIEnhancementError.invalidURL(config.baseURL)
        }

        if config.provider != .ollama && (config.apiKey == nil || config.apiKey?.isEmpty == true) {
            throw AIEnhancementError.missingAPIKey(config.provider)
        }

        if config.provider == .anthropic {
            return try await enhanceAnthropic(text: text, config: config, url: url, session: session)
        } else {
            return try await enhanceOpenAICompatible(text: text, config: config, url: url, session: session)
        }
    }

    private static func enhanceOpenAICompatible(
        text: String,
        config: AIEnhancementConfiguration,
        url: URL,
        session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let key = config.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": config.systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": config.temperature
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.executeDataTask(for: request)
        } catch {
            throw AIEnhancementError.requestFailed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AIEnhancementError.httpError(statusCode: http.statusCode, body: bodyText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AIEnhancementError.invalidResponse(raw)
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func enhanceAnthropic(
        text: String,
        config: AIEnhancementConfiguration,
        url: URL,
        session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        if let key = config.apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }

        let body: [String: Any] = [
            "model": config.model,
            "system": config.systemPrompt,
            "messages": [
                ["role": "user", "content": text]
            ],
            "max_tokens": 1024,
            "temperature": config.temperature
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.executeDataTask(for: request)
        } catch {
            throw AIEnhancementError.requestFailed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AIEnhancementError.httpError(statusCode: http.statusCode, body: bodyText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstBlock = contentArray.first,
              let contentText = firstBlock["text"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AIEnhancementError.invalidResponse(raw)
        }

        return contentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Synchronous wrapper for CLI execution
    public static func enhanceBlocking(
        text: String,
        config: AIEnhancementConfiguration = AIEnhancementConfiguration()
    ) throws -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String, Error>?

        Task {
            do {
                let enhanced = try await enhance(text: text, config: config)
                result = .success(enhanced)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        switch result {
        case .success(let res):
            return res
        case .failure(let err):
            throw err
        case .none:
            throw AIEnhancementError.requestFailed("Unknown timeout")
        }
    }
}
