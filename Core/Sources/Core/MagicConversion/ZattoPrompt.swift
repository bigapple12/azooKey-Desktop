/// ざっと変換の LLM プロンプトを組み立てる。
///
/// ざっと変換は「スペースで区切らず一気に入力した読み」を LLM で自然な日本語に
/// 変換する機能。Zenzai（ローカルのかな漢字変換）が苦手とする同音異義語の
/// 文脈判別・日英混在文・打ち間違い訂正を LLM 側で補うことを狙いとする。
public enum ZattoPrompt {
    public static func build(kanaText: String, rawText: String, contextPrompt: String, candidateCount: Int = 3) -> String {
        let contextSection = contextPrompt.isEmpty ? "" : """
        文脈:
        \(contextPrompt)

        """
        // 生入力（かな変換前の打鍵列）も渡す。英単語はかな変換で壊れる
        // （ghostty → gほsっty）ため、原型は生入力からしか復元できない
        let rawSection = rawText.isEmpty || rawText == kanaText ? "" : """
        生入力（ローマ字）: `\(rawText)`

        """
        return """
        日本語IMEの変換エンジンとして、入力された「読み」を文脈に合う自然な日本語に変換せよ。
        - 読みを厳守（語の追加・削除・言い換え禁止）
        - 同音異義語は文脈で判別
        - 読みに英字が残っている部分の解釈は生入力を参照し、次の優先順で扱う:
          1. ローマ字の打ち間違い（欠落・余分・隣接キー）なら、意図した日本語に訂正する（例: 生入力 desne → ですね）
          2. 実在する英単語（製品名・技術用語・一般英語）なら、英語表記のまま使う（例: ghostty）
          3. 英字の断片をアポストロフィ等で無理に英語化してはならない
        - 異なる候補を\(candidateCount)個、最も自然な順に。説明不要

        \(contextSection)\(rawSection)読み: `\(kanaText)`
        """
    }
}
