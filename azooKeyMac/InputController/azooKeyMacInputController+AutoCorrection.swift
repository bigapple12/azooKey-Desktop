import Cocoa
import Core
import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary

// MARK: - Pre-Commit AI Correction (確定前AI校正)
extension azooKeyMacInputController {

    /// composing中に呼ばれる。800msデバウンス付きでAI校正をトリガーする
    @MainActor
    func triggerPreCommitAICorrection() {
        let mode = Config.AutoCorrectionMode().value
        guard mode != .off else { return }
        guard Config.AIBackendPreference().value != .off else { return }

        let minLength = Config.AutoCorrectionMinLength().value
        let convertTarget = self.segmentsManager.convertTarget
        guard convertTarget.count >= minLength else { return }

        // 前回の校正タスクをキャンセル
        self.pendingCorrectionTask?.cancel()

        // 800msデバウンス付き校正タスクを開始
        self.pendingCorrectionTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let textToCorrect = self.segmentsManager.liveConversionText ?? self.segmentsManager.convertTarget
            await self.performPreCommitCorrection(text: textToCorrect)
        }
    }

    /// Space押下時（候補選択モード突入時）にデバウンスなしで即座にAI校正をリクエストする
    @MainActor
    func requestImmediateAICorrection() {
        let mode = Config.AutoCorrectionMode().value
        guard mode != .off else { return }
        guard Config.AIBackendPreference().value != .off else { return }

        let minLength = Config.AutoCorrectionMinLength().value
        let convertTarget = self.segmentsManager.convertTarget
        guard convertTarget.count >= minLength else { return }

        // 既にAI候補がある場合はスキップ
        // （デバウンスタスクが既に完了している場合）

        // 前回の校正タスクをキャンセル
        self.pendingCorrectionTask?.cancel()

        self.pendingCorrectionTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let textToCorrect = self.segmentsManager.liveConversionText ?? self.segmentsManager.convertTarget
            await self.performPreCommitCorrection(text: textToCorrect)
        }
    }

    /// AI校正リクエストの実行（3秒タイムアウト付き）
    /// 結果を segmentsManager.setAICandidates で渡し、候補ウィンドウを更新する
    @MainActor
    private func performPreCommitCorrection(text: String) async {
        let aiBackendPref = Config.AIBackendPreference().value
        guard aiBackendPref != .off else { return }

        // 実行時にもminLengthを再判定（デバウンス中にBackspace等で短くなった場合）
        let minLength = Config.AutoCorrectionMinLength().value
        guard text.count >= minLength else { return }

        let backend: AIBackend
        switch aiBackendPref {
        case .foundationModels:
            backend = .foundationModels
        case .openAI:
            backend = .openAI
        case .off:
            return
        }

        let prompt = Config.AutoCorrectionPrompt().value
        let fullPrompt = "\(prompt)\n\nテキスト: \(text)"
        let apiKey = Config.OpenAiApiKey().value
        let modelName = Config.OpenAiModelName().value

        if backend == .openAI && apiKey.isEmpty {
            self.segmentsManager.appendDebugMessage("AICorrection: APIキー未設定")
            return
        }

        let endpoint = Config.OpenAiApiEndpoint().value.isEmpty
            ? Config.OpenAiApiEndpoint.default
            : Config.OpenAiApiEndpoint().value

        // stale検出用: リクエスト前のconvertTargetを保存
        let convertTargetBeforeRequest = self.segmentsManager.convertTarget

        self.segmentsManager.appendDebugMessage("AICorrection: リクエスト送信 '\(text)'")

        do {
            // 3秒タイムアウト: TaskGroupでレース
            let corrected = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { @Sendable in
                    try await AIClient.sendTextTransformRequest(
                        fullPrompt,
                        backend: backend,
                        modelName: modelName,
                        apiKey: apiKey,
                        apiEndpoint: endpoint,
                        logger: { @MainActor [weak self] message in
                            self?.segmentsManager.appendDebugMessage("AICorrection: \(message)")
                        }
                    )
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    throw CancellationError()
                }

                guard let result = try await group.next() else {
                    throw CancellationError()
                }
                group.cancelAll()
                return result
            }

            guard !Task.isCancelled else { return }

            // stale検出: convertTargetが変わっていたら結果を破棄
            guard self.segmentsManager.convertTarget == convertTargetBeforeRequest else {
                self.segmentsManager.appendDebugMessage("AICorrection: stale検出 - 結果を破棄")
                return
            }

            // 差分ガード
            guard self.validateCorrection(original: text, corrected: corrected) else {
                return
            }

            self.segmentsManager.appendDebugMessage("AICorrection: 候補追加 '\(corrected)'")
            self.segmentsManager.setAICandidates([corrected])
            self.refreshCandidateWindow()
        } catch {
            self.segmentsManager.appendDebugMessage("AICorrection: エラー - \(error.localizedDescription)")
        }
    }

    /// 差分ガード: 修正が安全かチェック
    private func validateCorrection(original: String, corrected: String) -> Bool {
        // 同一テキスト: 修正不要
        if original == corrected {
            self.segmentsManager.appendDebugMessage("AICorrection: 修正なし（同一テキスト）")
            return false
        }

        // 差分ガード: 文字数変化が±20%を超える場合は破棄
        let originalLen = original.count
        let correctedLen = corrected.count
        let lenDiff = abs(originalLen - correctedLen)
        let threshold = max(1, Int(Double(originalLen) * 0.2))

        if lenDiff > threshold {
            self.segmentsManager.appendDebugMessage("AICorrection: 差分ガード不通過 (変化: \(lenDiff)文字, 閾値: \(threshold)文字)")
            return false
        }

        return true
    }
}
