//
//  VideoStorage.swift
//  Rugby AS
//
//  試合動画を端末のドキュメントディレクトリ（MatchVideos/ 配下）に
//  保存・削除するユーティリティ。SwiftData にはファイル名だけを保持する。
//  画像（ImageStorage）と違い、動画は大きいのでコピーのみで加工しない。
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum VideoStorage {
    static var directory: URL {
        URL.documentsDirectory.appendingPathComponent("MatchVideos", isDirectory: true)
    }

    static func url(named name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func exists(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(named: name).path)
    }

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 外部の動画ファイルを MatchVideos/ にコピーして、ファイル名を返す。
    /// ファイルアプリ経由の URL はセキュリティスコープ付きのことがあるので対応する。
    static func importVideo(from sourceURL: URL) throws -> String {
        try ensureDirectory()
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let name = UUID().uuidString + "." + ext
        try FileManager.default.copyItem(at: sourceURL, to: url(named: name))
        return name
    }

    static func delete(named name: String) {
        try? FileManager.default.removeItem(at: url(named: name))
    }

    /// 写真ライブラリのピッカーが直接 MatchVideos/ に書き込むための受け口。
    /// PhotosPicker → loadTransferable(type: PickedMatchVideo.self) で使う。
    struct PickedMatchVideo: Transferable {
        let fileName: String

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { picked in
                SentTransferredFile(VideoStorage.url(named: picked.fileName))
            } importing: { received in
                try VideoStorage.ensureDirectory()
                let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
                let name = UUID().uuidString + "." + ext
                try FileManager.default.copyItem(at: received.file, to: VideoStorage.url(named: name))
                return PickedMatchVideo(fileName: name)
            }
        }
    }
}
