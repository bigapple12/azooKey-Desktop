import Core
import Testing

private func disposition(
    event: KeyEventCore,
    state: ConverterInputState = .none,
    language: InputLanguage = .japanese,
    hasPendingKeyEvents: Bool = false
) -> ConverterClientEventDisposition {
    ConverterClientEventRouter.disposition(
        event: event,
        context: .init(
            acknowledgedInputState: state,
            acknowledgedInputLanguage: language,
            hasPendingKeyEvents: hasPendingKeyEvents
        )
    )
}

@Test func printableJapaneseInputIsSentToServer() {
    #expect(
        disposition(
            event: KeyEventCore(
                modifierFlags: [],
                characters: "a",
                charactersIgnoringModifiers: "a",
                keyCode: 0
            )
        ) == .sendToServer
    )
}

@Test func backspaceFallsThroughWhenAcknowledgedStateIsEmpty() {
    #expect(
        disposition(
            event: KeyEventCore(
                modifierFlags: [],
                characters: nil,
                charactersIgnoringModifiers: nil,
                keyCode: 51
            )
        ) == .fallthroughToApplication
    )
}

@Test func backspaceIsConsumedWhileEarlierKeyEventIsPending() {
    #expect(
        disposition(
            event: KeyEventCore(
                modifierFlags: [],
                characters: nil,
                charactersIgnoringModifiers: nil,
                keyCode: 51
            ),
            hasPendingKeyEvents: true
        ) == .sendToServer
    )
}

@Test func commandShortcutAlwaysFallsThroughWhileServerIsDelayed() {
    #expect(
        disposition(
            event: KeyEventCore(
                modifierFlags: [.command],
                characters: "c",
                charactersIgnoringModifiers: "c",
                keyCode: 8
            ),
            state: .composing,
            hasPendingKeyEvents: true
        ) == .fallthroughToApplication
    )
}

@Test func unknownControlShortcutIsConsumedOnlyDuringComposition() {
    let event = KeyEventCore(
        modifierFlags: [.control],
        characters: "q",
        charactersIgnoringModifiers: "q",
        keyCode: 12
    )

    #expect(disposition(event: event) == .fallthroughToApplication)
    #expect(disposition(event: event, state: .composing) == .sendToServer)
}

@Test func zattoConvertFallsThroughWhenSuggestionDisabled() {
    // Ctrl+J（ざっと変換）は AI バックエンド無効時・未入力時はアプリへ素通り
    let event = KeyEventCore(
        modifierFlags: [.control],
        characters: "j",
        charactersIgnoringModifiers: "j",
        keyCode: 38
    )

    #expect(disposition(event: event) == .fallthroughToApplication)
    #expect(disposition(event: event, state: .composing) == .fallthroughToApplication)
}

@Test func zattoConvertIsSentToServerWhenSuggestionEnabled() {
    let event = KeyEventCore(
        modifierFlags: [.control],
        characters: "j",
        charactersIgnoringModifiers: "j",
        keyCode: 38
    )
    let disposition = ConverterClientEventRouter.disposition(
        event: event,
        context: .init(
            acknowledgedInputState: .composing,
            enableSuggestion: true
        )
    )
    #expect(disposition == .sendToServer)
}

private func provisionalText(
    event: KeyEventCore,
    state: ConverterInputState = .none,
    language: InputLanguage = .japanese
) -> String? {
    ConverterClientEventRouter.provisionalComposingText(
        event: event,
        context: .init(
            acknowledgedInputState: state,
            acknowledgedInputLanguage: language
        )
    )
}

@Test func provisionalComposingTextReturnsTypedCharacterForCompositionStart() {
    let text = provisionalText(
        event: KeyEventCore(
            modifierFlags: [],
            characters: "k",
            charactersIgnoringModifiers: "k",
            keyCode: 40
        )
    )
    #expect(text == "k")
}

@Test func provisionalComposingTextIsNilForControlShortcut() {
    // Ctrl+S (suggest) は composition を開始しないため暫定 marked text を置かない
    let text = provisionalText(
        event: KeyEventCore(
            modifierFlags: [.control],
            characters: "s",
            charactersIgnoringModifiers: "s",
            keyCode: 1
        )
    )
    #expect(text == nil)
}

@Test func provisionalComposingTextIsNilForEnterKey() {
    let text = provisionalText(
        event: KeyEventCore(
            modifierFlags: [],
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36
        )
    )
    #expect(text == nil)
}

@Test func provisionalComposingTextIsNilForCommandShortcut() {
    let text = provisionalText(
        event: KeyEventCore(
            modifierFlags: [.command],
            characters: "c",
            charactersIgnoringModifiers: "c",
            keyCode: 8
        )
    )
    #expect(text == nil)
}
