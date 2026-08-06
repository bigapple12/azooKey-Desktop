# ざっと変換（Zatto）モード 設計メモ

作成: 2026-08-05 / 更新: 2026-08-06 / ステータス: フェーズ1 実装・実機検証済み

## フェーズ1 実測結果（2026-08-06）

- トリガー: **Ctrl+J**（composing 中のみ。ひらがな変換の Ctrl+J を上書き — F6 で代替可。旧 Alt+J ツール（Hammerspoon）は Ctrl+T へ移設して住み分け）
- `きしゃがきしゃできしゃした` → **記者が汽車で帰社した**（Gemini flash / flash-lite とも正解。Zenzai は「記者が記者で記者した」、Apple Foundation Models は「電車が…」と読み無視で不合格）
- `ghosttywotukatteiru` → **ghosttyを使っている**（生入力併記により英単語復元に成功。かなだけ渡した初版は「誤作動を使っている」と誤変換した）
- レイテンシ: gemini-flash-latest ~3秒 → gemini-flash-lite-latest + 候補3 + 短縮プロンプトで **1秒強**
- out-of-band 送信の効果確認: LLM 応答待ち中もタイプ・Esc が通常動作
- 運用メモ: LLM バックエンドは設定「いい感じ変換」と共用（OpenAI API + Gemini 互換エンドポイント）。フォークの署名が原作者の App Group と不一致のため、初回に macOS のアプリデータ分離ダイアログが出る（許可で OK）

打ち間違いを気にせずスペースも打たず「ざっと」入力し、いい感じの日本語に変換できる IME モードを azooKey-Desktop 上に作る。名称は「ざっと変換」、コード識別子は `Zatto`。

## UX 方針（実測に基づく確定事項）

**トリガーレスを最優先する。** 類似アプリ（クラウド LLM 型）の実測で「毎回の明示トリガー（Shift+Space）+ 2〜3 秒のレイテンシ + 専用アプリへの入力方式」は常用に耐えないことを確認した。一方 azooKey のライブ変換は、スペースなしの通常文を体感ゼロレイテンシで正しく変換できる（実測: `kyouhakaigigaookutetsukareta` → 「今日は会議が多くて疲れた」）。

したがって:

- **主役は Zenzai ライブ変換のまま**。ユーザーの操作モデルを変えない（打つ → Enter で確定）
- **LLM は補助**。曖昧シグナル検出時に非同期で発火し、良い候補が届いたら候補ウィンドウに追加する。LLM 待ちの間も入力は止まらない（2〜3 秒のレイテンシを体感から消す）
- 明示的な補正キーも 1 つ用意する（変換結果が気に入らない時だけ押す）

## LLM 補正が価値を出す場面（Zenzai の実測弱点）

| 場面 | Zenzai 実測 | LLM 補正後の期待 |
|------|------------|----------------|
| 同音異義語の文脈判別 | `kishagakishadekishashita` → 記者が記者で記者した | 汽車が貴社で帰社した |
| 日英混在文 | `ghostty` → gほsッty | 英単語をそのまま保持 |
| 打ち間違い訂正 | かな段階で固定される | 生ローマ字を渡せば LLM が吸収 |

発火シグナル（dotfiles の Alt+J ツールで実証済みのロジックを移植）:

- 同じ読みの文節が複数ある（`_ruby_repeated` 方式）
- かな化後に英字が残る（日英混在）
- 明示キー押下

## アーキテクチャ

### 差し込みポイント

調査（2026-08-05、探索エージェント 3 系統）の結論:

- **`.replaceSuggestion`（いい感じ変換）と同型に作るのが本命**。「LLM 候補リストを保持 → ↑↓/Tab 選択 → Enter 確定 → Esc で復帰」の状態機械・専用候補ウィンドウ・XPC 非同期・stale ガード（Server/Client 二重）がすべて先例として存在する
- ただし**トリガーレス方針により、独立モードではなく「ライブ変換への候補注入」が第一候補**。`SegmentsManager` の `additionalCandidates` 経路（別ソース候補を既存の選択動線に合流させる既成の仕組み）に LLM 候補を載せる
- **LLM 要求は `OrderedAsyncCommandQueue` に乗せない**（直列キューが詰まりタイプも Esc も効かなくなる）。`ConverterServerClient` にキューをバイパスする out-of-band 送信を新設する
- `InputState` に case を足す場合は Client / Server 両方で同一挙動が必須（`InputState.event` は両側で実行される純関数）

### LLM バックエンド

既存の MagicConversion 基盤を再利用する:

- `AIClient`（OpenAI / Apple FoundationModels の 2 バックエンド、構造化出力で複数候補、Keychain、設定 UI、接続テスト済み）
- OpenAI 互換エンドポイントで Gemini も使用可
- プロンプトは新設（既存の `Prompt.dictionary` は変換対象文字列がプロンプト選択キーになっており、任意入力で誤ヒットするため通さない）
- LLM に渡す入力: かな + 生ローマ字の両方を渡す形から検証（タイポ耐性は生ローマ字が有利）。前後 100 文字の文脈取得は既存実装を流用

### 移植する実証済みパターン（旧ブランチ feature/ai-correction-candidates + Alt+J ツール）

- AI 候補を `Candidate` 型として既存候補列に混ぜる（確定・学習・marked text 更新が既存経路で動く）
- 非同期 LLM の安全機構 4 層: タイムアウト / stale 検出（リクエスト前後で入力比較）/ 差分ガード / 重複リクエスト抑止
- `getRomanTextSegments()`（composition から生ローマ字を取得）
- 候補選択の UI 装飾（AI 候補への sparkles アイコン等）はデータの渡し方を `ConverterCandidatePresentation` に合わせて作り直し

## 前提（解決済み）

- Ghostty での 1 打鍵目漏れは修正済み（`89230c2`）。Ghostty は handle の戻り値ではなく keyDown 中の同期 setMarkedText 有無で IME 消費を判定するため、preedit が空の時に暫定 marked text を同期セットする方式で解決
- bundle ID はフォーク用に `dev.bigapple12.*`（`43b3ab4`、upstream に持ち出さない）

## フェーズ計画

- **フェーズ 1（シグナル検出 + 明示キー）**: `_ruby_repeated` 相当と英字残りの検出を Server 側に実装。まず明示キー（例: Ctrl+J）で「現在の composition 全体を LLM 変換して候補ウィンドウに追加候補として出す」を動かす。out-of-band 送信もここで作る
- **フェーズ 2（自動発火）**: シグナル検出時に自動で LLM 要求を発行し、届いた候補を `additionalCandidates` に注入。ライブ変換の邪魔をしない（先頭候補は変えず、追加候補として提示）
- **フェーズ 3（磨き込み）**: 学習との統合、日英混在の専用処理、レイテンシ計測と調整、設定 UI

各フェーズで実機（Ghostty + GUI アプリ）確認を必須とする。

## 決めごと

- 名称: 「ざっと変換」/ `Zatto`。**nospace という語は使わない**
- upstream への PR は現時点では出さない（フォーク内運用）
