import Foundation
import KanaKanjiConverterModule
import SwiftUtils

/// Shift+英字を交えて入力した場合の英字候補を調整する。
///
/// ローマ字入力中に Shift で大文字を打つと、読みに大文字英字が残る（例: `Gほsty`）。
/// これは「英字をそのまま入力したい」合図だが、変換エンジンは英字候補を安定して
/// 生成しない（学習データがある場合のみ出る）。また Shift は英字入力の合図であって
/// capitalize の意図とは限らない。
///
/// そこで、語頭付近に大文字がある場合は生入力（打鍵列そのもの）から英字候補を合成し、
/// 小文字化したもの（例: `ghosty`）を第一候補、打鍵どおり（例: `Ghosty`）を第二候補
/// として先頭に挿入する。エンジンが既に英字候補を出している場合の小文字化バリアント
/// 挿入も併せて行う。
public enum ShiftEnglishCandidateAdjuster {
    /// Shift 大文字を英字入力の合図とみなす範囲（生入力の先頭からの文字数）。
    /// Shift を押すタイミングが遅れて2文字目以降が大文字になるケースを救う一方、
    /// 文中の大文字（日本語文の途中に現れる英字など）では発動させない。
    private static let triggerPrefixCount = 3

    /// Shift 合図がない通常入力で、生入力アルファベット候補を挿入する位置（0-indexed）
    private static let rawCandidateIndexForEnglishWord = 1
    private static let rawCandidateIndexForNonWord = 4

    /// mainResults 用の調整。以下を順に行う。
    /// 1. 既存英字候補の小文字化バリアント挿入
    /// 2. Shift 大文字が合図の場合: 生入力から合成した英字候補を先頭に挿入
    /// 3. それ以外の英字打鍵: 生入力そのものを候補に挿入
    ///    （英語として成立する単語なら2番目、そうでなければ5番目あたり）
    /// - Parameters:
    ///   - candidates: 変換候補列（順序は優先度順）
    ///   - convertTarget: 現在の読み（例: `Gほsty`、`gHおsty`）
    ///   - rawInput: かな変換前の生の打鍵列（例: `Ghosty`）
    ///   - composingInputCount: 現在の `ComposingText.input` の要素数（whole 候補の composingCount 用）
    ///   - isEnglishWord: 英語として成立する単語かの判定（テスト時に注入可能）
    /// - Returns: 調整後の候補列
    public static func adjustWholeCandidates(
        candidates: [Candidate],
        convertTarget: String,
        rawInput: String,
        composingInputCount: Int,
        isEnglishWord: (String) -> Bool = EnglishWordChecker.isEnglishWord
    ) -> [Candidate] {
        var candidates = adjust(candidates: candidates, convertTarget: convertTarget)
        let ruby = convertTarget.toKatakana()
        if shouldSynthesize(rawInput: rawInput) {
            let lowered = rawInput.lowercased()
            // 合成候補と同じテキストの既存候補は取り除き、先頭に置き直す
            let synthesizedTexts = Set([lowered, rawInput])
            candidates.removeAll { synthesizedTexts.contains($0.text) }
            let baseValue = candidates.first?.value ?? -10
            var synthesized = [
                makeSynthesizedCandidate(text: lowered, ruby: ruby, value: baseValue.nextUp.nextUp, composingInputCount: composingInputCount)
            ]
            if rawInput != lowered {
                synthesized.append(
                    makeSynthesizedCandidate(text: rawInput, ruby: ruby, value: baseValue.nextUp, composingInputCount: composingInputCount)
                )
            }
            return synthesized + candidates
        }
        if shouldInsertRawCandidate(rawInput: rawInput) {
            candidates.removeAll { $0.text == rawInput }
            let targetIndex = isEnglishWord(rawInput) ? rawCandidateIndexForEnglishWord : rawCandidateIndexForNonWord
            let index = min(targetIndex, candidates.count)
            let value = index == 0 ? (candidates.first?.value ?? -10).nextUp : candidates[index - 1].value.nextDown
            candidates.insert(
                makeSynthesizedCandidate(text: rawInput, ruby: ruby, value: value, composingInputCount: composingInputCount),
                at: index
            )
        }
        return candidates
    }

    /// 読みに大文字英字が含まれる場合、対応する英字候補の先頭を小文字化したバリアントを挿入する
    /// - Parameters:
    ///   - candidates: 変換候補列（順序は優先度順）
    ///   - convertTarget: 現在の読み（例: `Gほsっty`、`gHおsty`）
    /// - Returns: 小文字化バリアントを挿入した候補列
    public static func adjust(candidates: [Candidate], convertTarget: String) -> [Candidate] {
        // Shift 由来の大文字が読みのどこかに含まれる場合のみ発動する
        guard convertTarget.contains(where: { $0.isASCII && $0.isUppercase }), let head = convertTarget.first else {
            return candidates
        }
        var seenTexts = Set(candidates.map(\.text))
        var result: [Candidate] = []
        result.reserveCapacity(candidates.count + 4)
        for candidate in candidates {
            if let lowered = loweredVariantText(of: candidate.text, head: head), !seenTexts.contains(lowered) {
                var variant = candidate
                variant.text = lowered
                // 学習データも小文字化したテキストに揃える（元候補の分節情報は引き継がない）
                let ruby = candidate.data.map(\.ruby).joined()
                variant.data = [DicdataElement(word: lowered, ruby: ruby, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: candidate.value)]
                // 後段で value ソートされても元候補より前に来るよう、僅かに高い評価値を与える
                variant.value = candidate.value.nextUp
                result.append(variant)
                seenTexts.insert(lowered)
            }
            result.append(candidate)
        }
        return result
    }

    /// 直接確定（スペースを押さない Enter）や composing 表示に使う英字テキストを返す
    ///
    /// Shift 大文字で英字入力が始まっている場合、小文字化した打鍵列（例: `ghostty`）を返す。
    /// 発動条件を満たさない場合は nil。
    public static func directEnglishText(rawInput: String) -> String? {
        guard shouldSynthesize(rawInput: rawInput) else {
            return nil
        }
        return rawInput.lowercased()
    }

    /// 生入力から英字候補を合成すべきか
    ///
    /// 条件: 生入力が空でない ASCII のみの列で、英字を含み、
    /// 先頭 `triggerPrefixCount` 文字以内に大文字英字がある。
    private static func shouldSynthesize(rawInput: String) -> Bool {
        guard !rawInput.isEmpty, rawInput.allSatisfy(\.isASCII) else {
            return false
        }
        guard rawInput.contains(where: \.isLetter) else {
            return false
        }
        return rawInput.prefix(triggerPrefixCount).contains(where: \.isUppercase)
    }

    /// Shift 合図がない場合でも、生入力そのものを候補に挿入すべきか
    ///
    /// 条件: 2文字以上の ASCII のみの列で、英字を含む。
    private static func shouldInsertRawCandidate(rawInput: String) -> Bool {
        guard rawInput.count >= 2, rawInput.allSatisfy(\.isASCII) else {
            return false
        }
        return rawInput.contains(where: \.isLetter)
    }

    private static func makeSynthesizedCandidate(text: String, ruby: String, value: PValue, composingInputCount: Int) -> Candidate {
        Candidate(
            text: text,
            value: value,
            composingCount: .inputCount(composingInputCount),
            lastMid: MIDData.一般.mid,
            data: [DicdataElement(word: text, ruby: ruby, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: value)]
        )
    }

    /// 小文字化バリアントを作るべき候補なら、そのテキストを返す
    ///
    /// 条件: 読み先頭と同じ英字（大文字小文字は不問）の大文字で始まる ASCII のみの候補で、
    /// 2文字目以降に小文字を含む（`GHOSTTY` のような全大文字候補は対象外）か、1文字のみ。
    private static func loweredVariantText(of text: String, head: Character) -> String? {
        guard let first = text.first, first.isASCII, first.isUppercase,
              first.lowercased() == head.lowercased() else {
            return nil
        }
        guard text.allSatisfy(\.isASCII) else {
            return nil
        }
        let rest = text.dropFirst()
        guard rest.isEmpty || rest.contains(where: \.isLowercase) else {
            return nil
        }
        return first.lowercased() + rest
    }
}
