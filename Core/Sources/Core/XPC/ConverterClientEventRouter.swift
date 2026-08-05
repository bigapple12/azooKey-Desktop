import Foundation

/// InputMethodKit の同期 `handle` が返すイベント所有権だけを判断する。
///
/// 変換状態の本体は ConverterServer が所有する。Client は Server が最後に返した
/// 読み取り専用の状態を使い、明らかな application shortcut を同期的に通す。
/// Server の応答待ちがある間は状態が進んでいる可能性があるため、Command shortcut
/// 以外を保守的に consume し、生のキー入力が application へ漏れることを防ぐ。
public enum ConverterClientEventDisposition: Sendable, Equatable {
    case sendToServer
    case fallthroughToApplication
}

public struct ConverterClientEventRoutingContext: Sendable, Equatable {
    public var acknowledgedInputState: ConverterInputState
    public var acknowledgedInputLanguage: InputLanguage
    public var hasPendingKeyEvents: Bool
    public var liveConversionEnabled: Bool
    public var enableDebugWindow: Bool
    public var enableSuggestion: Bool
    public var typeBackSlash: Bool

    public init(
        acknowledgedInputState: ConverterInputState = .none,
        acknowledgedInputLanguage: InputLanguage = .japanese,
        hasPendingKeyEvents: Bool = false,
        liveConversionEnabled: Bool = true,
        enableDebugWindow: Bool = false,
        enableSuggestion: Bool = false,
        typeBackSlash: Bool = false
    ) {
        self.acknowledgedInputState = acknowledgedInputState
        self.acknowledgedInputLanguage = acknowledgedInputLanguage
        self.hasPendingKeyEvents = hasPendingKeyEvents
        self.liveConversionEnabled = liveConversionEnabled
        self.enableDebugWindow = enableDebugWindow
        self.enableSuggestion = enableSuggestion
        self.typeBackSlash = typeBackSlash
    }
}

public enum ConverterClientEventRouter {
    public static func disposition(
        event: KeyEventCore,
        context: ConverterClientEventRoutingContext
    ) -> ConverterClientEventDisposition {
        // Command shortcut は composition の有無にかかわらず application が所有する。
        if event.modifierFlags.contains(.command) {
            return .fallthroughToApplication
        }

        // 未応答イベントがある場合、acknowledgedInputState は古い可能性がある。
        // ここで fallthrough するとタイムアウトした文字が英字として漏れるため、
        // Server が順番に処理できるようイベントを consume する。
        if context.hasPendingKeyEvents {
            return .sendToServer
        }

        let inputState = context.acknowledgedInputState.inputState
        let userAction = UserAction.getUserAction(
            eventCore: event,
            inputLanguage: context.acknowledgedInputLanguage,
            typeBackSlash: context.typeBackSlash
        )
        let (action, _) = inputState.event(
            eventCore: event,
            userAction: userAction,
            inputLanguage: context.acknowledgedInputLanguage,
            liveConversionEnabled: context.liveConversionEnabled,
            enableDebugWindow: context.enableDebugWindow,
            enableSuggestion: context.enableSuggestion
        )
        if case .fallthrough = action {
            return .fallthroughToApplication
        }
        return .sendToServer
    }

    /// `handle` が同期的に返る前に client へ置く暫定 marked text を返す。
    ///
    /// Ghostty 等の一部クライアントは `handle` の戻り値ではなく、keyDown の処理中に
    /// `setMarkedText` / `insertText` が同期的に呼ばれたかどうかで IME がキーを
    /// 消費したと判断する。marked text の反映は Server 応答後（非同期）のため、
    /// preedit が空の状態から composition を開始する 1 打鍵目で、これらの
    /// クライアントは生のキー入力を application 側へ流してしまう。
    /// このメソッドは acknowledged 状態のミラーで「composition を開始/継続する
    /// 入力」と判断できる場合に限り暫定文字列を返す。正しい表示は Server 応答後の
    /// marked text 更新が上書きする。
    public static func provisionalComposingText(
        event: KeyEventCore,
        context: ConverterClientEventRoutingContext
    ) -> String? {
        guard !event.modifierFlags.contains(.command) else {
            return nil
        }
        let inputState = context.acknowledgedInputState.inputState
        let userAction = UserAction.getUserAction(
            eventCore: event,
            inputLanguage: context.acknowledgedInputLanguage,
            typeBackSlash: context.typeBackSlash
        )
        let (action, _) = inputState.event(
            eventCore: event,
            userAction: userAction,
            inputLanguage: context.acknowledgedInputLanguage,
            liveConversionEnabled: context.liveConversionEnabled,
            enableDebugWindow: context.enableDebugWindow,
            enableSuggestion: context.enableSuggestion
        )
        let text: String
        switch action {
        case .appendToMarkedText(let string):
            text = string
        case .appendPieceToMarkedText(let pieces):
            text = String(pieces.compactMap { piece -> Character? in
                switch piece {
                case .character(let character):
                    return character
                case .key(let intention, let input, _):
                    return intention ?? input
                case .compositionSeparator:
                    return nil
                }
            })
        default:
            return nil
        }
        return text.isEmpty ? nil : text
    }
}
