@testable import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

/// Shift 大文字で始めた英字入力を「スペースなしで直接確定」する手癖のテスト。
/// composing 表示と Enter 確定の両方が小文字化した打鍵列になることを確認する。
@MainActor
@Suite("Shift英字入力の直接確定", .serialized)
struct ShiftEnglishDirectCommitTests {
    private func makeManager() -> SegmentsManager {
        SegmentsManager(
            kanaKanjiConverter: .withDefaultDictionary(),
            applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            containerURL: nil,
            context: .init(useZenzai: false)
        )
    }

    private func type(_ manager: SegmentsManager, _ text: String) {
        for ch in text {
            manager.insertAtCursorPosition(pieces: [.key(intention: nil, input: ch, modifiers: [])], inputStyle: .roman2kana)
        }
    }

    @Test("Shift+G で始めた入力は composing 表示が小文字打鍵列になる")
    func composingMarkedTextShowsLoweredRawInput() {
        let manager = makeManager()
        type(manager, "Ghostty")
        let marked = manager.getCurrentMarkedText(inputState: .composing)
        #expect(marked.text.map(\.content) == ["ghostty"])
    }

    @Test("Shift+G で始めた入力は Enter 直接確定で小文字打鍵列になる")
    func directCommitReturnsLoweredRawInput() {
        let manager = makeManager()
        type(manager, "Ghostty")
        #expect(manager.commitMarkedText(inputState: .composing) == "ghostty")
    }

    @Test("Shift が遅れて2文字目が大文字でも直接確定は小文字打鍵列になる")
    func directCommitForLateShift() {
        let manager = makeManager()
        type(manager, "gHostty")
        #expect(manager.commitMarkedText(inputState: .composing) == "ghostty")
    }

    @Test("大文字を含まない通常のローマ字入力は従来どおりかな表示・かな確定")
    func japaneseTypingIsUnaffected() {
        let manager = makeManager()
        type(manager, "kyou")
        let marked = manager.getCurrentMarkedText(inputState: .composing)
        #expect(marked.text.map(\.content) == ["きょう"])
        #expect(manager.commitMarkedText(inputState: .composing) == "きょう")
    }

    @Test("日本語文の途中の大文字では英字表示にならない")
    func lateUppercaseInSentenceIsUnaffected() {
        let manager = makeManager()
        type(manager, "kyouhaG")
        let marked = manager.getCurrentMarkedText(inputState: .composing)
        #expect(marked.text.map(\.content) == ["きょうはG"])
    }
}
