import XCTest
@testable import NepNep

/// engines.yml 파싱과 원격 응답 읽기 (#21 후속)
///
/// 이 둘이 이 기능에서 손으로 확인하기 가장 번거로운 자리다 — YAML은 사용자가
/// 직접 고치고, 응답은 서버마다 모양이 조금씩 다르다.
final class EngineCatalogTests: XCTestCase {

    // MARK: - YAML

    func testParseReadsAllFields() throws {
        let engines = try EngineCatalog.parse("""
        engines:
          - id: macmini
            name: 맥미니
            kind: openAI
            url: http://macmini.tailc6bd83.ts.net:8927
            model: whisper-large-v3-turbo
            language: ko
            note: 집 맥에 붙습니다
        """)

        XCTAssertEqual(engines.count, 1)
        let engine = try XCTUnwrap(engines.first)
        XCTAssertEqual(engine.id, "macmini")
        XCTAssertEqual(engine.name, "맥미니")
        XCTAssertEqual(engine.kind, .openAI)
        XCTAssertEqual(engine.baseURL?.host(), "macmini.tailc6bd83.ts.net")
        XCTAssertEqual(engine.model, "whisper-large-v3-turbo")
        XCTAssertEqual(engine.language, "ko")
        XCTAssertEqual(engine.note, "집 맥에 붙습니다")
        XCTAssertFalse(engine.diarizes)
        XCTAssertFalse(engine.needsAPIKey)
    }

    /// 기기 안 엔진은 주소가 없어도 통과해야 한다
    func testParseAllowsOnDeviceWithoutURL() throws {
        let engines = try EngineCatalog.parse("""
        engines:
          - id: speechTranscriber
            kind: onDevice
        """)
        XCTAssertEqual(engines.first?.baseURL, nil)
        // name을 안 적으면 id를 그대로 쓴다
        XCTAssertEqual(engines.first?.name, "speechTranscriber")
    }

    func testParseFlagsAPIKeyReference() throws {
        let engines = try EngineCatalog.parse("""
        engines:
          - id: deepgram
            kind: deepgram
            url: https://api.deepgram.com
            apiKeyRef: deepgram
            diarizes: true
        """)
        XCTAssertTrue(engines.first?.needsAPIKey == true)
        XCTAssertTrue(engines.first?.diarizes == true)
    }

    func testParseRejectsMissingEngines() {
        XCTAssertThrowsError(try EngineCatalog.parse("something: else"))
    }

    func testParseRejectsUnknownKind() {
        XCTAssertThrowsError(try EngineCatalog.parse("""
        engines:
          - id: x
            kind: whisper.cpp
            url: https://example.com
        """))
    }

    /// 주소를 빼먹은 원격 엔진은 목록에 들어오면 안 된다 — 고르고 나서야
    /// 실패하는 것보다 파싱에서 걸러 기본값으로 돌아가는 편이 낫다
    func testParseRejectsRemoteWithoutURL() {
        XCTAssertThrowsError(try EngineCatalog.parse("""
        engines:
          - id: groq
            kind: openAI
            model: whisper-large-v3-turbo
        """))
    }

    func testParseRejectsSchemelessURL() {
        XCTAssertThrowsError(try EngineCatalog.parse("""
        engines:
          - id: groq
            kind: openAI
            url: api.groq.com
        """))
    }

    /// 번들에 구워 나가는 기본 목록이 항상 읽혀야 한다
    func testBundledCatalogParses() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "engines", withExtension: "yml")
            ?? Bundle.main.url(forResource: "engines", withExtension: "yml"))
        let engines = try EngineCatalog.parse(String(contentsOf: url, encoding: .utf8))
        XCTAssertFalse(engines.isEmpty)
        XCTAssertEqual(engines.first?.id, EngineID.speechTranscriber.rawValue)
    }

    // MARK: - 응답 읽기

    func testParseOpenAIUsesTopLevelWords() throws {
        let json = Data("""
        {"text":"안녕하세요 반갑습니다",
         "segments":[{"start":0,"end":2,"text":"안녕하세요 반갑습니다"}],
         "words":[{"word":"안녕하세요 ","start":0.0,"end":1.0,"probability":0.9},
                  {"word":"반갑습니다 ","start":1.0,"end":2.0,"probability":0.8}]}
        """.utf8)

        let words = try RemoteTranscriptionEngine.parseOpenAI(json)
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words.first?.text, "안녕하세요 ")
        XCTAssertEqual(words.first?.start, 0)
        XCTAssertEqual(words.last?.confidence ?? 0, 0.8, accuracy: 0.001)
    }

    /// 단어 타임스탬프를 안 주는 서버는 구간 단위로라도 받아 둔다
    func testParseOpenAIFallsBackToSegments() throws {
        let json = Data("""
        {"text":"안녕하세요","segments":[{"start":0,"end":2.5,"text":"안녕하세요"}]}
        """.utf8)

        let words = try RemoteTranscriptionEngine.parseOpenAI(json)
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.end, 2.5)
    }

    func testParseDeepgramBuildsSpeakerSegments() throws {
        let json = Data("""
        {"results":{"channels":[{"alternatives":[{"words":[
          {"word":"안녕","punctuated_word":"안녕,","start":0.0,"end":0.5,"confidence":0.99,"speaker":0},
          {"word":"하세요","start":0.5,"end":1.0,"confidence":0.98,"speaker":0},
          {"word":"반가워요","start":1.2,"end":2.0,"confidence":0.97,"speaker":1}
        ]}]}]}}
        """.utf8)

        let (words, segments) = try RemoteTranscriptionEngine.parseDeepgram(json)
        XCTAssertEqual(words.count, 3)
        // 구두점이 붙은 표기가 있으면 그쪽을 쓴다
        XCTAssertEqual(words.first?.text, "안녕, ")

        let speakers = try XCTUnwrap(segments)
        XCTAssertEqual(speakers.count, 2)
        XCTAssertEqual(speakers.first?.speakerKey, "speaker0")
        XCTAssertEqual(speakers.first?.end, 1.0)
        XCTAssertEqual(speakers.last?.speakerKey, "speaker1")
    }

    func testParseDeepgramRejectsUnexpectedShape() {
        XCTAssertThrowsError(try RemoteTranscriptionEngine.parseDeepgram(Data("{}".utf8)))
    }
}
