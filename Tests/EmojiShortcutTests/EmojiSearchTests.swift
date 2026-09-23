import XCTest
@testable import EmojiShortcut

final class EmojiSearchTests: XCTestCase {
    func testOmedDoesNotMatchDromedaryKeyword() {
        let camel = EmojiEntry(
            emoji: "🐪", name: "ラクダ", englishName: "camel",
            keywords: ["dromedary", "camel"]
        )
        XCTAssertFalse(camel.matchesLocalQuery("omed"))
        XCTAssertTrue(camel.matchesLocalQuery("drom"))
    }

    func testEnglishWordsAndAliasesStillMatchByPrefix() {
        let party = EmojiEntry(
            emoji: "🎉", name: "クラッカー", englishName: "party popper",
            keywords: ["tada", "celebrate"]
        )
        XCTAssertTrue(party.matchesLocalQuery("tada"))
        XCTAssertTrue(party.matchesLocalQuery("pop"))
    }

    func testGoodnightKeywordStillSupportsFuzzyLocalSearch() {
        let sleepy = EmojiEntry(
            emoji: "🥱", name: "あくびした顔", englishName: "yawning face",
            keywords: ["goodnight", "sleepy"]
        )
        XCTAssertTrue(sleepy.matchesLocalQuery("good"))
    }

    func testCountryFlagsAreExcludedFromSearchCandidates() {
        let japan = EmojiEntry(emoji: "🇯🇵", name: "日本", englishName: "flag: Japan", keywords: ["japan"])
        let smile = EmojiEntry(emoji: "🙂", name: "微笑む", englishName: "slightly smiling face", keywords: ["smile"])
        XCTAssertTrue(japan.isFlag)
        XCTAssertFalse(smile.isFlag)
    }

    func testRemoteSearchWaitsForVeryShortUnfinishedRomaji() {
        XCTAssertFalse(EmojiSearchPolicy.shouldSearchRemote(""))
        XCTAssertTrue(EmojiSearchPolicy.shouldSearchRemote("", hasContext: true))
        XCTAssertFalse(EmojiSearchPolicy.shouldSearchRemote("omed"))
        XCTAssertTrue(EmojiSearchPolicy.shouldSearchRemote("omede"))
        XCTAssertTrue(EmojiSearchPolicy.shouldSearchRemote("omedetou"))
        XCTAssertTrue(EmojiSearchPolicy.shouldSearchRemote("suki"))
        XCTAssertTrue(EmojiSearchPolicy.shouldSearchRemote("おめでとう"))
        XCTAssertTrue(EmojiSearchPolicy.shouldSearchRemote("iikanzi"))
        XCTAssertTrue(EmojiSearchPolicy.shouldSearchRemote("gakkari"))
    }

    func testEnterWaitsForSearchInsteadOfSendingUnfinishedShortcut() {
        XCTAssertEqual(EmojiSearchPolicy.selectionAction(candidateCount: 0, searchPending: true), .waitForSearch)
        XCTAssertEqual(EmojiSearchPolicy.selectionAction(candidateCount: 2, searchPending: true), .select)
        XCTAssertEqual(EmojiSearchPolicy.selectionAction(candidateCount: 0, searchPending: false), .passThrough)
    }

    func testContextModeFallsBackToTypedSearch() {
        XCTAssertTrue(EmojiSearchPolicy.usesContextSearch(
            requested: true, query: "", hasContext: true
        ))
        XCTAssertFalse(EmojiSearchPolicy.usesContextSearch(
            requested: true, query: "happy", hasContext: true
        ))
        XCTAssertFalse(EmojiSearchPolicy.usesContextSearch(
            requested: true, query: "", hasContext: false
        ))
    }

    func testColonContextSearchAutoAppliesItsFirstEmojiCandidate() {
        XCTAssertTrue(EmojiSearchPolicy.usesContextSearch(
            requested: true, query: "", hasContext: true
        ))
        XCTAssertTrue(EmojiSearchPolicy.shouldAutoApplyFirstCandidate(
            isContextMode: true, candidateCount: 3
        ))
        XCTAssertFalse(EmojiSearchPolicy.shouldAutoApplyFirstCandidate(
            isContextMode: true, candidateCount: 0
        ))
    }

    func testTypingAfterAutoAppliedEmojiResumesTextSearchAndShowsPanel() {
        let resume = EmojiSearchPolicy.textSearchResume(
            shortcut: ":", characters: "嬉"
        )
        XCTAssertEqual(resume?.shortcut, ":嬉")
        XCTAssertEqual(resume?.query, "嬉")
        XCTAssertTrue(EmojiSearchPolicy.shouldShowPanel(
            query: resume?.query ?? "", isContextMode: false
        ))
        XCTAssertFalse(EmojiSearchPolicy.shouldShowPanel(
            query: "", isContextMode: true
        ))
    }

    func testFastTypingAfterAutoAppliedEmojiKeepsEveryCharacter() {
        var resume = EmojiSearchPolicy.textSearchResume(
            shortcut: ":", characters: "o"
        )
        for character in ["h", "a", "n", "a"] {
            resume = EmojiSearchPolicy.textSearchResume(
                shortcut: resume?.shortcut ?? ":", characters: character
            )
        }
        XCTAssertEqual(resume?.shortcut, ":ohana")
        XCTAssertEqual(resume?.query, "ohana")
        XCTAssertTrue(EmojiSearchPolicy.shouldShowPanel(
            query: resume?.query ?? "", isContextMode: false
        ))
        XCTAssertEqual(EmojiSearchPolicy.typedTextToRestore(
            originalShortcut: ":", resumedShortcut: resume?.shortcut ?? ""
        ), "ohana", "検索への切り替えが失敗しても先頭のoを含む全文字を戻す")
    }

    func testJevPromptExplainsRomajiMoodQueries() {
        let instructions = JevClient.choiceInstructions
        XCTAssertTrue(instructions.contains("Japanese romaji"))
        XCTAssertFalse(instructions.contains("サイコー"))
        XCTAssertTrue(instructions.contains("return only the options"))
    }

    func testJevStateSendsOnlyTheTextBeingJudged() {
        XCTAssertEqual(JevClient.state(query: "omedetou", context: nil), "omedetou")
        XCTAssertEqual(
            JevClient.state(query: "", context: "めっちゃサイコー"),
            "めっちゃサイコー"
        )
        XCTAssertEqual(
            JevClient.state(query: "", context: "今日はめっちゃサイコー"),
            String("今日はめっちゃサイコー".suffix(10))
        )
        XCTAssertNotEqual(
            JevClient.cacheKey(query: "omedetou", context: "誕生日 "),
            JevClient.cacheKey(query: "omedetou", context: "卒業式 ")
        )
    }

    func testJevSearchModeDefaultsToTextAndCanBeChanged() {
        let suiteName = "JevSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(JevSettings.searchMode(using: defaults), .text)
        JevSettings.setSearchMode(.context, using: defaults)
        XCTAssertEqual(JevSettings.searchMode(using: defaults), .context)
        JevSettings.setSearchMode(.text, using: defaults)
        XCTAssertEqual(JevSettings.searchMode(using: defaults), .text)
    }

    func testLegacyContextSettingMigratesToMatchingSearchMode() {
        let enabledSuite = "JevSettingsLegacyEnabledTests.\(UUID().uuidString)"
        let enabledDefaults = UserDefaults(suiteName: enabledSuite)!
        defer { enabledDefaults.removePersistentDomain(forName: enabledSuite) }
        enabledDefaults.set(true, forKey: "SendPrecedingTextToJev")
        XCTAssertEqual(JevSettings.searchMode(using: enabledDefaults), .context)

        let disabledSuite = "JevSettingsLegacyDisabledTests.\(UUID().uuidString)"
        let disabledDefaults = UserDefaults(suiteName: disabledSuite)!
        defer { disabledDefaults.removePersistentDomain(forName: disabledSuite) }
        disabledDefaults.set(false, forKey: "SendPrecedingTextToJev")
        XCTAssertEqual(JevSettings.searchMode(using: disabledDefaults), .text)
    }
}
