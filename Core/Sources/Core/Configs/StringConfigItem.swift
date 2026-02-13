//
//  StringConfigItem.swift
//  azooKeyMac
//
//  Created by miwa on 2024/04/27.
//

import Foundation

protocol StringConfigItem: ConfigItem<String> {}

extension StringConfigItem {
    public var value: String {
        get {
            UserDefaults.standard.string(forKey: Self.key) ?? ""
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: Self.key)
        }
    }
}

extension Config {
    public struct ZenzaiProfile: StringConfigItem {
        public init() {}

        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.ZenzaiProfile"
    }
}

extension Config {
    /// OpenAIモデル名
    public struct OpenAiModelName: StringConfigItem {
        public init() {}

        public static let `default`: String = "gpt-4o-mini"
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiModelName"
    }

    /// OpenAI API エンドポイント
    public struct OpenAiApiEndpoint: StringConfigItem {
        public init() {}

        public static let `default` = "https://api.openai.com/v1/chat/completions"
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiApiEndpoint"

        public var value: String {
            get {
                let stored = UserDefaults.standard.string(forKey: Self.key) ?? ""
                return stored.isEmpty ? Self.default : stored
            }
            nonmutating set {
                UserDefaults.standard.set(newValue, forKey: Self.key)
            }
        }
    }

    /// プロンプト履歴（JSON形式で保存）
    struct PromptHistory: StringConfigItem {
        static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.PromptHistory"
    }

    /// 自動校正用システムプロンプト
    public struct AutoCorrectionPrompt: StringConfigItem {
        public init() {}
        public static let `default`: String = """
        日本語テキストの誤字脱字・文法を修正してください。
        日本語IMEが有効な状態で英語を入力した場合（例:「G大gぇ」→「Google」「へっろ」→「hello」）、意図した英語に復元してください。
        修正したテキストのみ返してください。変更不要の場合は元のテキストをそのまま返してください。
        """
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.autoCorrectionPrompt"

        public var value: String {
            get {
                let stored = UserDefaults.standard.string(forKey: Self.key) ?? ""
                return stored.isEmpty ? Self.default : stored
            }
            nonmutating set {
                UserDefaults.standard.set(newValue, forKey: Self.key)
            }
        }
    }
}
