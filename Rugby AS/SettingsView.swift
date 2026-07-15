//
//  SettingsView.swift
//  Rugby AS
//
//  設定画面。デフォルト自チーム名と、全記録のバックアップ(書き出し/読み込み)。
//  値は端末設定(UserDefaults)に保存し、試合をつくる画面が参照する。
//

import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultTeamName") private var defaultTeamName = ""
    @State private var isRestoreImporterPresented = false
    @State private var restoreResultMessage: String?
    @State private var backupShareItem: BackupShareItem?
    @State private var backupExportError: String?

    var body: some View {
        Form {
            Section {
                TextField("例: ○○大学", text: $defaultTeamName)
            } header: {
                Text("デフォルト自チーム名")
            } footer: {
                Text("試合をつくる画面のホームチームに、この名前が最初から入ります。")
            }

            Section {
                Button {
                    exportBackup()
                } label: {
                    Label("バックアップを書き出す", systemImage: "square.and.arrow.up")
                }

                Button {
                    isRestoreImporterPresented = true
                } label: {
                    Label("バックアップを読み込む", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("バックアップ")
            } footer: {
                Text("全記録・選手写真・試合時間設定を1つのファイルに書き出します(動画は含みません)。読み込みは「同じデータは上書き・無いものは追加」で、削除はされません。")
            }

            Section {
                Label(
                    "大事な大会の後は、バックアップの書き出しをおすすめします。",
                    systemImage: "externaldrive.badge.timemachine"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isRestoreImporterPresented,
            allowedContentTypes: [.json]
        ) { result in
            restoreBackup(from: result)
        }
        .sheet(item: $backupShareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert("バックアップの読み込み", isPresented: Binding(
            get: { restoreResultMessage != nil },
            set: { if !$0 { restoreResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { restoreResultMessage = nil }
        } message: {
            Text(restoreResultMessage ?? "")
        }
        .alert("バックアップの書き出し", isPresented: Binding(
            get: { backupExportError != nil },
            set: { if !$0 { backupExportError = nil } }
        )) {
            Button("OK", role: .cancel) { backupExportError = nil }
        } message: {
            Text(backupExportError ?? "")
        }
    }

    // タップされた時点でファイルを作り、出来上がったファイルを共有シートに渡す。
    private func exportBackup() {
        do {
            let url = try BackupManager.writeBackupFile(context: modelContext)
            backupShareItem = BackupShareItem(url: url)
        } catch {
            backupExportError = "書き出しに失敗しました。もう一度試してください。"
        }
    }

    private func restoreBackup(from result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }

        // ファイルアプリ経由のURLは、読む前に許可の取得が必要なことがある
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let summary = try BackupManager.restore(from: data, context: modelContext)
            restoreResultMessage = summary.message
        } catch let error as BackupError {
            restoreResultMessage = error.errorDescription
        } catch {
            restoreResultMessage = "読み込みに失敗しました。ファイルを確認してもう一度試してください。"
        }
    }
}

// 共有シートに渡す「書き出し済みファイル」。sheet(item:) で使うため Identifiable。
private struct BackupShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// iOS 標準の共有シート(UIActivityViewController)を SwiftUI から使う薄いラッパー。
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [
        Team.self,
        Player.self,
        Tournament.self,
        Match.self,
        StatEvent.self,
        MatchLineup.self,
        Substitution.self
    ], inMemory: true)
}
