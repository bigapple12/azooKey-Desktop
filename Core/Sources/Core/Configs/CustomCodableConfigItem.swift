//
//  LearningConfig.swift
//  azooKeyMac
//
//  Created by miwa on 2024/04/27.
//

import Foundation
import struct KanaKanjiConverterModuleWithDefaultDictionary.ConvertRequestOptions
import enum KanaKanjiConverterModuleWithDefaultDictionary.LearningType

protocol CustomCodableConfigItem: ConfigItem {
    static var `default`: Value { get }
}

extension CustomCodableConfigItem {
    public var value: Value {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.key) else {
                print(#file, #line, "data is not set yet")
                return Self.default
            }
            do {
                let decoded = try JSONDecoder().decode(Value.self, from: data)
                return decoded
            } catch {
                print(#file, #line, error)
                return Self.default
            }
        }
        nonmutating set {
            do {
                let encoded = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(encoded, forKey: Self.key)
            } catch {
                print(#file, #line, error)
            }
        }
    }
}

extension Config {
    /// ライブ変換を有効化する設定
    public struct Learning: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case inputAndOutput
            case onlyOutput
            case nothing

            public var learningType: LearningType {
                switch self {
                case .inputAndOutput:
                    .inputAndOutput
                case .onlyOutput:
                    .onlyOutput
                case .nothing:
                    .nothing
                }
            }
        }

        public init() {}
        static let `default`: Value = .inputAndOutput
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.learning"
    }
}

extension Config {
    public struct UserDictionaryEntry: Sendable, Codable, Identifiable {
        public init(word: String, reading: String, hint: String? = nil) {
            self.id = UUID()
            self.word = word
            self.reading = reading
            self.hint = hint
        }

        public var id: UUID
        public var word: String
        public var reading: String
        var hint: String?

        public var nonNullHint: String {
            get {
                hint ?? ""
            }
            set {
                if newValue.isEmpty {
                    hint = nil
                } else {
                    hint = newValue
                }
            }
        }
    }

    public struct UserDictionary: CustomCodableConfigItem {
        public struct Value: Codable, Sendable {
            public var items: [UserDictionaryEntry]
        }

        public var items: Value = Self.default

        public init(items: Value = Self.default) {
            self.items = items
        }

        public static let `default`: Value = .init(items: [
            .init(word: "azooKey", reading: "あずーきー", hint: "アプリ")
        ])
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.user_dictionary_temporal2"
    }

    public struct SystemUserDictionary: CustomCodableConfigItem {
        public struct Value: Codable, Sendable {
            public var lastUpdate: Date?
            public var items: [UserDictionaryEntry]
        }

        public var items: Value = Self.default

        public init(items: Value = Self.default) {
            self.items = items
        }

        public static let `default`: Value = .init(items: [])
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.system_user_dictionary"
    }
}

extension Config {
    /// 確定時AI校正モード
    public struct AutoCorrectionMode: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case off      // 無効
            case auto     // 自動置換
            case suggest  // 候補表示して選ばせる
        }
        public init() {}
        public static let `default`: Value = .off
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.autoCorrectionMode"
    }
}

extension Config {
    /// Zenzaiのパーソナライズ強度
    public struct ZenzaiPersonalizationLevel: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case off
            case soft
            case normal
            case hard

            public var alpha: Float {
                switch self {
                case .off:
                    0
                case .soft:
                    0.5
                case .normal:
                    1.0
                case .hard:
                    1.5
                }
            }
        }

        public init() {}
        public static let `default`: Value = .normal
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.zenzai.personalization_level"
    }
}

extension Config {
    public struct InputStyle: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case `default`
            case defaultAZIK
            case defaultKanaJIS
            case defaultKanaUS
            case custom
        }

        public init() {}
        public static let `default`: Value = .default
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.input_style"
    }
}

extension Config {
    /// キーボードレイアウトの設定
    public struct KeyboardLayout: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case qwerty
            case australian
            case colemak
            case dvorak
            case dvorakQwertyCommand

            public var layoutIdentifier: String {
                switch self {
                case .qwerty:
                    return "com.apple.keylayout.US"
                case .australian:
                    return "com.apple.keylayout.Australian"
                case .colemak:
                    return "com.apple.keylayout.Colemak"
                case .dvorak:
                    return "com.apple.keylayout.Dvorak"
                case .dvorakQwertyCommand:
                    return "com.apple.keylayout.DVORAK-QWERTYCMD"
                }
            }
        }

        public init() {}
        public static let `default`: Value = .qwerty
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.keyboard_layout"
    }

    /// プロンプトプリセット
    public struct PromptPreset: Sendable, Codable, Identifiable, Equatable {
        public init(id: UUID = UUID(), name: String, prompt: String) {
            self.id = id
            self.name = name
            self.prompt = prompt
        }
        public var id: UUID
        public var name: String
        public var prompt: String
    }

    /// AI校正プロンプトプリセット管理
    public struct AutoCorrectionPromptPresets: ConfigItem {
        public typealias Value = PresetsValue

        public struct PresetsValue: Codable, Sendable {
            public var presets: [PromptPreset]
            public var activePresetId: UUID?

            public init(presets: [PromptPreset], activePresetId: UUID? = nil) {
                self.presets = presets
                self.activePresetId = activePresetId
            }

            public var activePrompt: String {
                if let id = activePresetId,
                   let preset = presets.first(where: { $0.id == id }) {
                    return preset.prompt
                }
                return presets.first?.prompt ?? AutoCorrectionPrompt.default
            }
        }
        public init() {}
        public static let englishTranslationPrompt: String = """
        入力された日本語テキストを自然な英語に翻訳してください。
        翻訳結果のみ返してください。
        """

        public static let `default`: PresetsValue = .init(
            presets: [
                PromptPreset(name: "誤字修正", prompt: AutoCorrectionPrompt.default),
                PromptPreset(name: "英語翻訳", prompt: englishTranslationPrompt)
            ],
            activePresetId: nil
        )
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.autoCorrectionPromptPresets"

        public var value: PresetsValue {
            get {
                guard let data = UserDefaults.standard.data(forKey: Self.key) else {
                    // 初回: 旧 AutoCorrectionPrompt からの移行を試みる
                    let legacyKey = Config.AutoCorrectionPrompt.key
                    let legacyPrompt = UserDefaults.standard.string(forKey: legacyKey) ?? ""
                    let prompt = legacyPrompt.isEmpty ? AutoCorrectionPrompt.default : legacyPrompt
                    let migrated = PresetsValue(presets: [
                        PromptPreset(name: "誤字修正", prompt: prompt),
                        PromptPreset(name: "英語翻訳", prompt: Self.englishTranslationPrompt)
                    ])
                    // 移行結果を保存
                    if let encoded = try? JSONEncoder().encode(migrated) {
                        UserDefaults.standard.set(encoded, forKey: Self.key)
                    }
                    return migrated
                }
                do {
                    var decoded = try JSONDecoder().decode(PresetsValue.self, from: data)
                    // 移行: 英語翻訳プリセットが無ければ追加
                    if !decoded.presets.contains(where: { $0.name == "英語翻訳" }) {
                        decoded.presets.append(PromptPreset(name: "英語翻訳", prompt: Self.englishTranslationPrompt))
                        if let encoded = try? JSONEncoder().encode(decoded) {
                            UserDefaults.standard.set(encoded, forKey: Self.key)
                        }
                    }
                    return decoded
                } catch {
                    return Self.default
                }
            }
            nonmutating set {
                do {
                    let encoded = try JSONEncoder().encode(newValue)
                    UserDefaults.standard.set(encoded, forKey: Self.key)
                } catch {
                    print(#file, #line, error)
                }
            }
        }
    }

    public struct AIBackendPreference: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case off = "Off"
            case foundationModels = "Foundation Models"
            case openAI = "OpenAI API"
        }

        public init() {}

        public static var `default`: Value {
            // Migration: If user had OpenAI API enabled, preserve that setting
            let legacyKey = Config.Deprecated.EnableOpenAiApiKey.key
            if let legacyValue = UserDefaults.standard.object(forKey: legacyKey) as? Bool,
               legacyValue {
                return .openAI
            }
            return .off
        }
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.aiBackend"
    }
}
