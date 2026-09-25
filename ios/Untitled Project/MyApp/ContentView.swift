import SwiftUI

/// Drop-in replacement for the container app's default ContentView.swift.
/// Just onboarding text plus the Jev API key field — the keyboard extension
/// does the actual work.
struct ContentView: View {
    @State private var apiKey: String = JevKeyStore.read() ?? ""
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("使い方")
                        .font(.headline)
                    Text("設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加、でEmojichaoキーボードを有効化してください。テキスト入力中に地球儀キーで切り替えて使えます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Jev（任意の意味検索）") {
                    Text("設定すると、絵文字候補が文章の意味からより賢く選ばれるようになります。設定しなくてもローカル検索だけで動作します。利用にはキーボード側で「フルアクセスを許可」も必要です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SecureField("Jev APIキー", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button("保存") {
                        JevKeyStore.save(apiKey)
                        statusMessage = "保存しました"
                    }
                    Button("削除", role: .destructive) {
                        apiKey = ""
                        JevKeyStore.clear()
                        statusMessage = "削除しました"
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Emojichao")
        }
    }
}

#Preview {
    ContentView()
}
