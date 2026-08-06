import AppKit
import Foundation

/// 英語として成立する単語かどうかを OS のスペルチェッカーで判定する。
/// 変換エンジン内の `SpellChecker`（補完用）と同様に `NSSpellChecker` を使う。
public enum EnglishWordChecker {
    public static func isEnglishWord(_ word: String) -> Bool {
        // 1文字は既存の英字候補（大文字/全角等）で足りるため対象外
        guard word.count >= 2, word.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return false
        }
        let range = NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: "en",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }
}
