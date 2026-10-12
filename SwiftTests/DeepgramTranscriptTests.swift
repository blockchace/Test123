import XCTest
@testable import ChaceRecordings

final class DeepgramTranscriptTests: XCTestCase {
    func testEveryLanguageUsesNova3WithoutPuttingKeyInURL() {
        for language in TranscriptionLanguage.allCases {
            let url = DeepgramTranscript.endpoint(language: language)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            let params = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
            XCTAssertEqual(url.host, "api.deepgram.com")
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(params["model"], "nova-3")
            XCTAssertEqual(params["language"], language.rawValue)
            XCTAssertEqual(params["utterances"], "true")
            XCTAssertNil(params["key"])
        }
    }

    func testUtterancesBecomeReadableUTF8WithSpeakerAndTime() throws {
        let data = Data(#"{"results":{"utterances":[{"start":3.5,"speaker":0,"transcript":"Hola, ¿cómo estás?"},{"start":12,"speaker":1,"transcript":"Very well, gracias."}]}}"#.utf8)
        let result = try DeepgramTranscript.text(from: data, name: "Conversación", language: .multilingual)
        XCTAssertTrue(result.contains("Conversación"))
        XCTAssertTrue(result.contains("[00:00:03 · Hablante 1]"))
        XCTAssertTrue(result.contains("Hola, ¿cómo estás?"))
        XCTAssertTrue(result.contains("Hablante 2"))
        XCTAssertTrue(result.contains("Very well, gracias."))
    }

    func testPlainTranscriptFallbackAndEmptyResponse() throws {
        let data = Data(#"{"results":{"channels":[{"alternatives":[{"transcript":"Hello world."}]}]}}"#.utf8)
        XCTAssertTrue(try DeepgramTranscript.text(from: data, name: "Test", language: .english).contains("Hello world."))
        for response in [#"{"results":{"channels":[{"alternatives":[{"transcript":""}]}]}}"#, "{}", "not-json"] {
            XCTAssertThrowsError(try DeepgramTranscript.text(from: Data(response.utf8), name: "Test", language: .spanish))
        }
    }

    func testRejectedRequestsAreNeverTreatedAsSuccess() throws {
        try DeepgramTranscript.validate(status: 200)
        for status in [400, 401, 402, 403, 413, 429, 500, 503] {
            XCTAssertThrowsError(try DeepgramTranscript.validate(status: status))
        }
    }
}
