# コントリビューション

IssueやPull Requestを歓迎します。

## 開発

必要なもの：

- macOS 13以降
- XcodeとSwift 6

```sh
swift test
sh build-app.sh
open .build/EmojiShortcut.app
```

入力監視や文字置換に関する変更では、自動テストに加えて `Tests/AppCompatibilityChecklist.md` の確認も行ってください。

## Pull Request

- 変更の目的と利用者への影響を説明してください。
- 新しい挙動には可能な限りテストを追加してください。
- APIキー、証明書、公証資格情報、実際の入力内容をコミットしないでください。
- 外部へ送信する情報や必要な権限を変える場合は、`PRIVACY.md`とREADMEも更新してください。

