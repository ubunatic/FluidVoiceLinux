import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FluidVoiceLinuxCLICore

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("MockURLProtocol handler not set")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class AIEnhancementServiceTests: XCTestCase {
    override func invokeTest() {
        runWithTimeout { super.invokeTest() }
    }

    var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        super.tearDown()
    }

    func testDefaultConfigurations() {
        let config = AIEnhancementConfiguration(provider: .ollama)
        XCTAssertEqual(config.provider, .ollama)
        XCTAssertEqual(config.model, "llama3.2")
        XCTAssertEqual(config.baseURL, "http://localhost:11434/v1/chat/completions")

        let openai = AIEnhancementConfiguration(provider: .openai, apiKey: "sk-test")
        XCTAssertEqual(openai.model, "gpt-4o-mini")
        XCTAssertEqual(openai.baseURL, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(openai.apiKey, "sk-test")
    }

    func testOpenAICompatibleEnhancement() async throws {
        let expectedPrompt = "Hello world this is raw speech"
        let expectedEnhanced = "Hello, world! This is raw speech."

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test_key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let responseJSON: [String: Any] = [
                "choices": [
                    [
                        "message": [
                            "role": "assistant",
                            "content": expectedEnhanced
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseJSON)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let config = AIEnhancementConfiguration(
            provider: .openai,
            apiKey: "test_key"
        )

        let result = try await AIEnhancementService.enhance(text: expectedPrompt, config: config, session: session)
        XCTAssertEqual(result, expectedEnhanced)
    }

    func testAnthropicEnhancement() async throws {
        let expectedPrompt = "make a list one two three"
        let expectedEnhanced = "1. One\n2. Two\n3. Three"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic_key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

            let responseJSON: [String: Any] = [
                "content": [
                    [
                        "type": "text",
                        "text": expectedEnhanced
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseJSON)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let config = AIEnhancementConfiguration(
            provider: .anthropic,
            apiKey: "anthropic_key"
        )

        let result = try await AIEnhancementService.enhance(text: expectedPrompt, config: config, session: session)
        XCTAssertEqual(result, expectedEnhanced)
    }

    func testMissingAPIKeyThrows() async {
        let config = AIEnhancementConfiguration(provider: .openai, apiKey: "")
        do {
            _ = try await AIEnhancementService.enhance(text: "some text", config: config, session: session)
            XCTFail("expected missingAPIKey error")
        } catch {
            guard case AIEnhancementError.missingAPIKey(let p) = error else {
                return XCTFail("expected missingAPIKey, got \(error)")
            }
            XCTAssertEqual(p, .openai)
        }
    }
}
