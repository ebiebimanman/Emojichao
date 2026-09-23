# リリースチェックリスト

## リリース前

- [ ] ソースコードの配布条件を確認し、READMEおよび必要な場合は`LICENSE`と一致している
- [ ] 著作権者名が `2026 ebiebimanman` で統一されている
- [ ] Bundle IDとKeychainのサービス名が正式な値で一致している
- [ ] `CFBundleShortVersionString`と`CFBundleVersion`を更新した
- [ ] `swift test`が成功する
- [ ] `Tests/AppCompatibilityChecklist.md`を実アプリで確認した
- [ ] READMEと`PRIVACY.md`が実装の通信・権限・保存内容と一致している
- [ ] リポジトリにAPIキー、証明書、公証資格情報、個人情報がない

## 配布物の作成

```sh
sh scripts/release.sh
```

- [ ] Developer ID Applicationで署名されている
- [ ] Apple公証が成功している
- [ ] 公証チケットがステープルされている
- [ ] Gatekeeper検証が成功している
- [ ] `dist/EmojiShortcut-x.y.z.zip`を別のMacで展開・起動できる
- [ ] SHA-256チェックサムが生成されている

## GitHub

- [ ] タグを作成した（例：`v0.1.0`）
- [ ] GitHub Releaseのタイトルと変更点を書いた
- [ ] ZIPと`.sha256`をReleaseへ添付した
- [ ] Release画面からダウンロードしたZIPでも初回起動を確認した
- [ ] Private vulnerability reportingを有効にした
