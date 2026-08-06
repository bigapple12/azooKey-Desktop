import Core
import Foundation
import KanaKanjiConverterModule
import Testing

@Suite("ShiftEnglishCandidateAdjuster")
struct ShiftEnglishCandidateAdjusterTests {
    private func makeCandidate(_ text: String, value: PValue = -10) -> Candidate {
        Candidate(
            text: text,
            value: value,
            composingCount: .inputCount(text.count),
            lastMid: MIDData.一般.mid,
            data: [DicdataElement(word: text, ruby: "Gホスッティ", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: value)]
        )
    }

    @Test("先頭大文字の読みでは小文字化バリアントが直前に挿入される")
    func insertsLoweredVariant() {
        let result = ShiftEnglishCandidateAdjuster.adjust(
            candidates: [makeCandidate("Ghostty"), makeCandidate("ゴースト")],
            convertTarget: "Gほsっty"
        )
        #expect(result.map(\.text) == ["ghostty", "Ghostty", "ゴースト"])
    }

    @Test("小文字化バリアントは元候補より僅かに高い評価値を持つ")
    func loweredVariantHasHigherValue() {
        let result = ShiftEnglishCandidateAdjuster.adjust(
            candidates: [makeCandidate("Ghostty")],
            convertTarget: "Gほsっty"
        )
        #expect(result[0].value > result[1].value)
    }

    @Test("Shiftが遅れて2文字目が大文字になった読みでも小文字化バリアントが挿入される")
    func insertsLoweredVariantForLateShift() {
        let result = ShiftEnglishCandidateAdjuster.adjust(
            candidates: [makeCandidate("Ghosty"), makeCandidate("ゴースト")],
            convertTarget: "gHおsty"
        )
        #expect(result.map(\.text) == ["ghosty", "Ghosty", "ゴースト"])
    }

    @Test("読みに大文字がなければ何もしない")
    func lowercaseHeadIsUntouched() {
        let candidates = [makeCandidate("ghostty"), makeCandidate("ゴースト")]
        let result = ShiftEnglishCandidateAdjuster.adjust(candidates: candidates, convertTarget: "gほsっty")
        #expect(result.map(\.text) == ["ghostty", "ゴースト"])
    }

    @Test("読みの先頭がかなでも何もしない")
    func kanaHeadIsUntouched() {
        let candidates = [makeCandidate("今日")]
        let result = ShiftEnglishCandidateAdjuster.adjust(candidates: candidates, convertTarget: "きょう")
        #expect(result.map(\.text) == ["今日"])
    }

    @Test("全大文字候補には小文字化バリアントを作らない")
    func allUppercaseCandidateIsUntouched() {
        let result = ShiftEnglishCandidateAdjuster.adjust(
            candidates: [makeCandidate("GHOSTTY")],
            convertTarget: "Gほsっty"
        )
        #expect(result.map(\.text) == ["GHOSTTY"])
    }

    @Test("1文字だけの候補には小文字化バリアントを作る")
    func singleLetterCandidateGetsVariant() {
        let result = ShiftEnglishCandidateAdjuster.adjust(
            candidates: [makeCandidate("G")],
            convertTarget: "G"
        )
        #expect(result.map(\.text) == ["g", "G"])
    }

    @Test("小文字版が既に候補にある場合は重複挿入しない")
    func doesNotDuplicateExistingLoweredCandidate() {
        let result = ShiftEnglishCandidateAdjuster.adjust(
            candidates: [makeCandidate("Ghostty"), makeCandidate("ghostty")],
            convertTarget: "Gほsっty"
        )
        #expect(result.map(\.text) == ["Ghostty", "ghostty"])
    }

    @Test("非ASCIIを含む候補には作らない")
    func nonASCIICandidateIsUntouched() {
        let result = ShiftEnglishCandidateAdjuster.adjust(
            candidates: [makeCandidate("Gほsっty")],
            convertTarget: "Gほsっty"
        )
        #expect(result.map(\.text) == ["Gほsっty"])
    }

    @Test("読み先頭と異なる大文字で始まる候補には作らない")
    func differentHeadLetterIsUntouched() {
        let result = ShiftEnglishCandidateAdjuster.adjust(
            candidates: [makeCandidate("Xcode")],
            convertTarget: "Gほsっty"
        )
        #expect(result.map(\.text) == ["Xcode"])
    }

    @Test("小文字化バリアントの学習データは小文字テキストに揃う")
    func loweredVariantDataUsesLoweredWord() {
        let result = ShiftEnglishCandidateAdjuster.adjust(
            candidates: [makeCandidate("Ghostty")],
            convertTarget: "Gほsっty"
        )
        #expect(result[0].data.map(\.word) == ["ghostty"])
    }

    // MARK: - EnglishWordChecker（実物の NSSpellChecker 判定）

    @Test("実在する英単語を認識する")
    func realCheckerAcceptsEnglishWords() {
        #expect(EnglishWordChecker.isEnglishWord("hello"))
        #expect(EnglishWordChecker.isEnglishWord("world"))
    }

    @Test("英語として成立しない文字列を弾く")
    func realCheckerRejectsNonWords() {
        #expect(!EnglishWordChecker.isEnglishWord("qzxwvj"))
        #expect(!EnglishWordChecker.isEnglishWord("kyouha"))
        #expect(!EnglishWordChecker.isEnglishWord("a"))
    }

    // MARK: - adjustWholeCandidates（生入力からの合成）

    @Test("エンジンが英字候補を出さなくても生入力から合成して先頭に置く")
    func synthesizesFromRawInput() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: [makeCandidate("Gホsty"), makeCandidate("Gほsty")],
            convertTarget: "Gほsty",
            rawInput: "Ghosty",
            composingInputCount: 6
        )
        #expect(result.map(\.text) == ["ghosty", "Ghosty", "Gホsty", "Gほsty"])
    }

    @Test("Shiftが遅れて2文字目が大文字でも合成する")
    func synthesizesForLateShift() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: [makeCandidate("gHオsty")],
            convertTarget: "gHおsty",
            rawInput: "gHosty",
            composingInputCount: 6
        )
        #expect(result.map(\.text) == ["ghosty", "gHosty", "gHオsty"])
    }

    @Test("大文字がなければ先頭合成はせず、生入力候補の挿入に回る")
    func doesNotSynthesizeWithoutUppercase() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: [makeCandidate("ゴースト")],
            convertTarget: "gほsty",
            rawInput: "ghosty",
            composingInputCount: 6,
            isEnglishWord: { _ in false }
        )
        #expect(result.map(\.text) == ["ゴースト", "ghosty"])
    }

    @Test("大文字が4文字目以降なら先頭合成はしない")
    func doesNotSynthesizeForLateUppercase() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: [makeCandidate("今日はG")],
            convertTarget: "きょうはG",
            rawInput: "kyouhaG",
            composingInputCount: 7,
            isEnglishWord: { _ in false }
        )
        #expect(result.first?.text == "今日はG")
    }

    // MARK: - 生入力アルファベット候補（Shift 合図なし）

    @Test("英語として成立する単語は2番目に挿入される")
    func insertsEnglishWordAtSecondPosition() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: ["減る", "経る", "縁", "ヘル", "へる"].map { makeCandidate($0) },
            convertTarget: "へっぉ",
            rawInput: "hello",
            composingInputCount: 5,
            isEnglishWord: { $0 == "hello" }
        )
        #expect(result.map(\.text) == ["減る", "hello", "経る", "縁", "ヘル", "へる"])
    }

    @Test("英語として成立しない文字列は5番目に挿入される")
    func insertsNonWordAtFifthPosition() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: ["候補1", "候補2", "候補3", "候補4", "候補5", "候補6"].map { makeCandidate($0) },
            convertTarget: "gほsty",
            rawInput: "ghosty",
            composingInputCount: 6,
            isEnglishWord: { _ in false }
        )
        #expect(result.map(\.text) == ["候補1", "候補2", "候補3", "候補4", "ghosty", "候補5", "候補6"])
    }

    @Test("候補が少ない場合は末尾に挿入される")
    func appendsRawCandidateWhenListIsShort() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: [makeCandidate("候補1"), makeCandidate("候補2")],
            convertTarget: "gほsty",
            rawInput: "ghosty",
            composingInputCount: 6,
            isEnglishWord: { _ in false }
        )
        #expect(result.map(\.text) == ["候補1", "候補2", "ghosty"])
    }

    @Test("学習等で既に同じ生入力候補がある場合は指定位置に置き直す")
    func movesExistingRawCandidateToTargetPosition() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: ["減る", "経る", "縁", "hello"].map { makeCandidate($0) },
            convertTarget: "へっぉ",
            rawInput: "hello",
            composingInputCount: 5,
            isEnglishWord: { $0 == "hello" }
        )
        #expect(result.map(\.text) == ["減る", "hello", "経る", "縁"])
    }

    @Test("かなを含む生入力（英字以外の打鍵）には挿入しない")
    func doesNotInsertRawCandidateForNonASCII() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: [makeCandidate("今日")],
            convertTarget: "きょう",
            rawInput: "きょう",
            composingInputCount: 4,
            isEnglishWord: { _ in false }
        )
        #expect(result.map(\.text) == ["今日"])
    }

    @Test("1文字の生入力には挿入しない")
    func doesNotInsertRawCandidateForSingleChar() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: [makeCandidate("あ")],
            convertTarget: "あ",
            rawInput: "a",
            composingInputCount: 1,
            isEnglishWord: { _ in true }
        )
        #expect(result.map(\.text) == ["あ"])
    }

    @Test("合成候補と同じテキストの既存候補は先頭に置き直す")
    func deduplicatesSynthesizedTexts() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: [makeCandidate("Gホsty"), makeCandidate("Ghosty")],
            convertTarget: "Gほsty",
            rawInput: "Ghosty",
            composingInputCount: 6
        )
        #expect(result.map(\.text) == ["ghosty", "Ghosty", "Gホsty"])
    }

    @Test("合成候補は既存先頭候補より高い評価値を持つ")
    func synthesizedCandidatesHaveHigherValue() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: [makeCandidate("Gホsty", value: -5)],
            convertTarget: "Gほsty",
            rawInput: "Ghosty",
            composingInputCount: 6
        )
        #expect(result[0].value > result[1].value)
        #expect(result[1].value > result[2].value)
    }

    @Test("全部大文字で打った場合も小文字が第一候補・打鍵どおりが第二候補")
    func allUppercaseRawInput() {
        let result = ShiftEnglishCandidateAdjuster.adjustWholeCandidates(
            candidates: [],
            convertTarget: "VIM",
            rawInput: "VIM",
            composingInputCount: 3
        )
        #expect(result.map(\.text) == ["vim", "VIM"])
    }
}
