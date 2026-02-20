import Cocoa
import Core
import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary

// MARK: - Pre-Commit AI Correction (確定前AI校正)
extension azooKeyMacInputController {

    /// 組み込みモード時のローカル変換を即座に適用する
    @MainActor
    func applyBuiltInConversion() {
        guard let mode = self.activeBuiltInMode else { return }
        let convertTarget = self.segmentsManager.convertTarget
        guard !convertTarget.isEmpty else { return }

        let candidates: [String]
        switch mode {
        case .hiragana:
            candidates = [convertTarget.toHiragana()]
        case .katakana:
            // 末尾に未確定のローマ字（ASCII文字）がある場合はその部分を除外して変換
            let cleanTarget = convertTarget.prefix(while: { !$0.isASCII })
            if cleanTarget.isEmpty {
                // 全てASCII（入力途中）の場合は候補を更新しない
                return
            }
            candidates = [String(cleanTarget).toKatakana()]
        case .hankakuKatakana:
            let katakana = convertTarget.toKatakana()
            candidates = [katakana.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? katakana]
        case .fullWidthRoman:
            let roman = self.segmentsManager.getRomanText()
            candidates = [roman.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? roman]
        case .alphabet:
            candidates = self.generateAlphabetCandidates()
        case .off:
            // OFFモード: 通常の第一変換候補を表示
            if let text = self.segmentsManager.liveConversionText {
                candidates = [text]
            } else {
                candidates = []
            }
        }

        self.segmentsManager.aiCandidatesFirst = true
        self.segmentsManager.setAICandidates(candidates)
        self.refreshCandidateWindow()
    }

    /// alphabetモードの変換候補を生成（ケースバリエーション）
    @MainActor
    private func generateAlphabetCandidates() -> [String] {
        let segments = self.segmentsManager.getRomanTextSegments()
        guard !segments.isEmpty else { return [] }
        let raw = segments.joined()
        guard !raw.isEmpty else { return [] }

        var results: [String] = []
        var seen = Set<String>()
        let addUnique = { (s: String) in
            if seen.insert(s).inserted {
                results.append(s)
            }
        }

        // 1. lowercase（そのまま）
        addUnique(raw)
        // 2. UPPERCASE
        addUnique(raw.uppercased())
        // 3. 頭文字だけ大文字
        addUnique(raw.prefix(1).uppercased() + raw.dropFirst())

        // 複数セグメント（compositionSeparator区切り）がある場合はケース変換候補を追加
        if segments.count > 1 {
            // snake_case
            addUnique(segments.joined(separator: "_"))
            // camelCase
            addUnique(segments.enumerated().map { i, s in
                i == 0 ? s.lowercased() : s.prefix(1).uppercased() + s.dropFirst().lowercased()
            }.joined())
            // PascalCase
            addUnique(segments.map {
                $0.prefix(1).uppercased() + $0.dropFirst().lowercased()
            }.joined())
            // UPPER_SNAKE_CASE
            addUnique(segments.map { $0.uppercased() }.joined(separator: "_"))
        }

        return results
    }

    /// composing中に呼ばれる。800msデバウンス付きでAI校正をトリガーする
    @MainActor
    func triggerPreCommitAICorrection() {
        // 組み込みモード時はデバウンスなしで即座にローカル変換
        if self.activeBuiltInMode != nil {
            self.applyBuiltInConversion()
            return
        }

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

            self.isAICorrectionInProgress = true
            self.refreshMarkedText()
            let textToCorrect = self.segmentsManager.liveConversionText ?? self.segmentsManager.convertTarget
            await self.performPreCommitCorrection(text: textToCorrect)
        }
    }

    /// Space押下時（候補選択モード突入時）にデバウンスなしで即座にAI校正をリクエストする
    @MainActor
    func requestImmediateAICorrection() {
        // 組み込みモード時はローカル変換
        if self.activeBuiltInMode != nil {
            self.applyBuiltInConversion()
            return
        }

        let mode = Config.AutoCorrectionMode().value
        guard mode != .off else {
            NSLog("[azooKey] requestImmediateAICorrection: SKIP - mode is off")
            return
        }
        guard Config.AIBackendPreference().value != .off else {
            NSLog("[azooKey] requestImmediateAICorrection: SKIP - AI backend is off")
            return
        }

        let minLength = Config.AutoCorrectionMinLength().value
        let convertTarget = self.segmentsManager.convertTarget
        NSLog("[azooKey] requestImmediateAICorrection: convertTarget='%@' len=%d minLength=%d", convertTarget, convertTarget.count, minLength)
        guard convertTarget.count >= minLength else {
            NSLog("[azooKey] requestImmediateAICorrection: SKIP - too short")
            return
        }

        // 既にAI候補がある場合はスキップ
        // （デバウンスタスクが既に完了している場合）

        // 前回の校正タスクをキャンセル
        self.pendingCorrectionTask?.cancel()

        self.pendingCorrectionTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            self.isAICorrectionInProgress = true
            self.refreshMarkedText()
            self.refreshCandidateWindow()
            let textToCorrect = self.segmentsManager.liveConversionText ?? self.segmentsManager.convertTarget
            await self.performPreCommitCorrection(text: textToCorrect)
        }
    }

    /// AI校正リクエストの実行（3秒タイムアウト付き）
    /// 結果を segmentsManager.setAICandidates で渡し、候補ウィンドウを更新する
    @MainActor
    private func performPreCommitCorrection(text: String) async {
        defer {
            self.isAICorrectionInProgress = false
            self.refreshMarkedText()
        }
        NSLog("[azooKey] performPreCommitCorrection: text='%@'", text)
        let aiBackendPref = Config.AIBackendPreference().value
        guard aiBackendPref != .off else {
            NSLog("[azooKey] performPreCommitCorrection: SKIP - backend off")
            return
        }

        // 実行時にもminLengthを再判定（デバウンス中にBackspace等で短くなった場合）
        let minLength = Config.AutoCorrectionMinLength().value
        guard text.count >= minLength else {
            NSLog("[azooKey] performPreCommitCorrection: SKIP - too short")
            return
        }

        // 翻訳プリセット以外で、ASCII比率が高い文字列はスキップ
        let activePrompt = Config.AutoCorrectionPromptPresets().value.activePrompt
        let isTranslation = activePrompt.contains("翻訳")
        if !isTranslation && self.shouldSkipAICorrection(text: text) {
            NSLog("[azooKey] performPreCommitCorrection: SKIP - high ASCII ratio")
            return
        }

        // 同一テキストへの重複リクエストをスキップ
        if text == self.lastCorrectionInput && !self.segmentsManager.aiCandidateIndices.isEmpty {
            NSLog("[azooKey] performPreCommitCorrection: SKIP - same input, candidates exist")
            return
        }

        let backend: AIBackend
        switch aiBackendPref {
        case .foundationModels:
            backend = .foundationModels
        case .openAI:
            backend = .openAI
        case .off:
            return
        }

        // プリセットからプロンプトを取得（フォールバック: 旧設定）
        let prompt = Config.AutoCorrectionPromptPresets().value.activePrompt
        let candidateCount = max(1, min(5, Config.AutoCorrectionCandidateCount().value))
        let apiKey = Config.OpenAiApiKey().value
        let modelName = Config.OpenAiModelName().value

        NSLog("[azooKey] performPreCommitCorrection: prompt='%@' candidateCount=%d model='%@' apiKey=%@",
              String(prompt.prefix(50)), candidateCount, modelName, apiKey.isEmpty ? "EMPTY" : "SET(\(apiKey.count)chars)")

        if backend == .openAI && apiKey.isEmpty {
            NSLog("[azooKey] performPreCommitCorrection: SKIP - API key empty")
            self.segmentsManager.appendDebugMessage("AICorrection: APIキー未設定")
            return
        }

        let endpoint = Config.OpenAiApiEndpoint().value.isEmpty
            ? Config.OpenAiApiEndpoint.default
            : Config.OpenAiApiEndpoint().value

        // stale検出用: リクエスト前のconvertTargetを保存
        let convertTargetBeforeRequest = self.segmentsManager.convertTarget

        self.segmentsManager.appendDebugMessage("AICorrection: リクエスト送信 '\(text)' (候補数: \(candidateCount))")

        do {
            if candidateCount == 1 {
                // 候補数1: 既存の sendTextTransformRequest を使用（後方互換）
                let fullPrompt = "\(prompt)\n\nテキスト: \(text)"
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

                NSLog("[azooKey] performPreCommitCorrection: API result='%@'", corrected)
                guard !Task.isCancelled else {
                    NSLog("[azooKey] performPreCommitCorrection: cancelled after API call")
                    return
                }

                guard self.segmentsManager.convertTarget == convertTargetBeforeRequest else {
                    NSLog("[azooKey] performPreCommitCorrection: stale detected")
                    self.segmentsManager.appendDebugMessage("AICorrection: stale検出 - 結果を破棄")
                    return
                }

                guard self.validateCorrection(original: text, corrected: corrected) else {
                    NSLog("[azooKey] performPreCommitCorrection: validation failed")
                    return
                }

                NSLog("[azooKey] performPreCommitCorrection: adding candidate '%@'", corrected)
                self.segmentsManager.appendDebugMessage("AICorrection: 候補追加 '\(corrected)'")
                self.lastCorrectionInput = text
                self.segmentsManager.setAICandidates([corrected])
                self.refreshCandidateWindow()
            } else {
                // 候補数 > 1: sendMultiCorrectionRequest を使用
                let fullPrompt = "\(prompt)\n\n\(candidateCount)個の候補を返してください。\n\nテキスト: \(text)"
                let results = try await withThrowingTaskGroup(of: [String].self) { group in
                    group.addTask { @Sendable in
                        try await AIClient.sendMultiCorrectionRequest(
                            fullPrompt,
                            candidateCount: candidateCount,
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

                guard self.segmentsManager.convertTarget == convertTargetBeforeRequest else {
                    self.segmentsManager.appendDebugMessage("AICorrection: stale検出 - 結果を破棄")
                    return
                }

                // 各候補を validateCorrection でフィルタし、AI候補同士の重複も除去
                var seen = Set<String>()
                let validCorrections = results.filter { candidate in
                    guard self.validateCorrection(original: text, corrected: candidate) else { return false }
                    return seen.insert(candidate).inserted
                }

                if !validCorrections.isEmpty {
                    self.segmentsManager.appendDebugMessage("AICorrection: \(validCorrections.count)個の候補追加")
                    self.lastCorrectionInput = text
                    self.segmentsManager.setAICandidates(validCorrections)
                    self.refreshCandidateWindow()
                }
            }
        } catch {
            NSLog("[azooKey] performPreCommitCorrection: ERROR - %@", error.localizedDescription)
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

        // 翻訳プリセットかどうかを判定（翻訳時は文字数が大きく変わるため差分ガードを緩和）
        let activePrompt = Config.AutoCorrectionPromptPresets().value.activePrompt
        let isTranslation = activePrompt.contains("翻訳")

        // 差分ガード: 誤字修正は±50%、翻訳は±300%
        let originalLen = original.count
        let correctedLen = corrected.count
        let lenDiff = abs(originalLen - correctedLen)
        let ratio = isTranslation ? 3.0 : 0.5
        let threshold = max(2, Int(Double(originalLen) * ratio))

        if lenDiff > threshold {
            self.segmentsManager.appendDebugMessage("AICorrection: 差分ガード不通過 (変化: \(lenDiff)文字, 閾値: \(threshold)文字)")
            return false
        }

        return true
    }

    /// ASCII比率が高い文字列（コード/英文）をスキップすべきか判定
    private func shouldSkipAICorrection(text: String) -> Bool {
        let asciiCount = text.unicodeScalars.filter { $0.isASCII }.count
        let totalCount = text.unicodeScalars.count
        guard totalCount > 0 else { return true }
        let ratio = Double(asciiCount) / Double(totalCount)
        return ratio > 0.5
    }
}
