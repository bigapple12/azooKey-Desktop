import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

// ざっと変換: composition 全体（読み）を LLM で自然な日本語に変換し、
// 結果を置換候補（replaceSuggestions）として提示する。
//
// 「いい感じ変換」（requestReplaceSuggestion）と同じ器を使うが、
// - プロンプトは ZattoPrompt 専用（Prompt.dictionary の辞書分岐を通さない）
// - 要求は Client が out-of-band 経路で送るため、LLM 応答待ちの間も
//   キーイベントは通常どおり処理される。そのため応答時には composition や
//   InputState が変わっている可能性があり、stale ガードを両方に掛ける
extension ConverterServer {
    @MainActor
    func requestZattoConversion(session: ConverterSession) async throws {
        session.clearReplaceSuggestions()
        guard !session.manager.isEmpty else {
            return
        }
        let backend: AIBackend
        switch session.config.aiBackendPreference {
        case .off:
            return
        case .foundationModels:
            backend = .foundationModels
        case .openAI:
            backend = .openAI
        }
        let composingText = session.manager.convertTarget
        let contextPrompt = session.config.includeContextInAITransform ? session.replaceSuggestionPromptContext() : ""
        let request = OpenAIRequest(
            prompt: "",
            target: composingText,
            modelName: session.config.openAIModelName.isEmpty ? Config.OpenAiModelName.default : session.config.openAIModelName,
            promptOverride: ZattoPrompt.build(
                kanaText: composingText,
                rawText: session.manager.rawInputText,
                contextPrompt: contextPrompt
            )
        )
        let predictions = try await AIClient.sendRequest(
            request,
            backend: backend,
            apiKey: session.config.openAIAPIKey.value,
            apiEndpoint: session.config.openAIEndpoint.isEmpty ? Config.OpenAiApiEndpoint.default : session.config.openAIEndpoint
        )
        // stale ガード: 応答待ちの間に composition が変わった / Esc 等で
        // replaceSuggestion 状態を抜けた場合は結果を破棄する
        guard session.manager.convertTarget == composingText else {
            return
        }
        guard case .replaceSuggestion = session.inputState else {
            return
        }
        session.replaceSuggestions = predictions.map { text in
            Candidate(
                text: text,
                value: PValue(0),
                composingCount: .surfaceCount(composingText.count),
                lastMid: 0,
                data: [],
                actions: [],
                inputable: true
            )
        }
        if !session.replaceSuggestions.isEmpty {
            session.replaceSuggestionSelectionIndex = 0
        }
    }
}
