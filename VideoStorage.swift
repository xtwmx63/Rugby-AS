//
//  VideoStorage.swift
//  Rugby AS
//
//  試合動画を端末のドキュメントディレクトリに保存・読込・削除する。
//  SwiftData にはファイル名だけを保持する。
//

import Foundation

enum VideoStorage {
    nonisolated private static let matchVideoMapKey = "matchVideoFileNamesByMatchID"
    nonisolated private static let copyBufferSize = 4 * 1024 * 1024

    nonisolated private static var directory: URL {
        URL.documentsDirectory.appendingPathComponent("MatchVideos", isDirectory: true)
    }

    nonisolated static func save(
        from sourceURL: URL,
        progress: ((Double, Int64, Int64) -> Void)? = nil
    ) throws -> String {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let name = UUID().uuidString + "." + fileExtension
        let destinationURL = directory.appendingPathComponent(name)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let totalBytes = try fileSize(for: sourceURL)
        try validateAvailableStorage(requiredFileSize: totalBytes)
        progress?(0, 0, totalBytes)

        do {
            try copyItem(
                from: sourceURL,
                to: destinationURL,
                totalBytes: totalBytes,
                progress: progress
            )
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        excludeFromBackup(destinationURL)
        return name
    }

    /// 動画をiCloudバックアップの対象から外す。
    /// 試合動画は数GBあり、含めるとユーザーのiCloud容量を圧迫するため。
    /// (動画は写真アプリ等から再取り込みできるので、消えても復元手段がある)
    nonisolated private static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    /// 既に取り込み済みの動画にも、まとめてバックアップ除外を適用する(起動時に1回)
    nonisolated static func excludeAllVideosFromBackup() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for file in files {
            excludeFromBackup(file)
        }
    }

    nonisolated static func videoNames(for matchID: UUID) -> [String] {
        matchVideoMap[matchID.uuidString, default: []]
    }

    nonisolated static func videoName(for matchID: UUID) -> String? {
        videoNames(for: matchID).first
    }

    nonisolated static func setVideoNames(_ names: [String], for matchID: UUID) {
        var map = matchVideoMap
        let cleanedNames = names.filter { !$0.isEmpty }
        if cleanedNames.isEmpty {
            map.removeValue(forKey: matchID.uuidString)
        } else {
            map[matchID.uuidString] = cleanedNames
        }
        UserDefaults.standard.set(map, forKey: matchVideoMapKey)
    }

    nonisolated static func appendVideoNames(_ names: [String], for matchID: UUID) {
        let appendedNames = videoNames(for: matchID) + names.filter { !$0.isEmpty }
        setVideoNames(appendedNames, for: matchID)
    }

    nonisolated static func setVideoName(_ name: String?, for matchID: UUID) {
        if let name {
            setVideoNames([name], for: matchID)
        } else {
            setVideoNames([], for: matchID)
        }
    }

    nonisolated static func removeVideoName(_ name: String, for matchID: UUID) {
        setVideoNames(videoNames(for: matchID).filter { $0 != name }, for: matchID)
    }

    nonisolated static func deleteVideo(for matchID: UUID) {
        deleteVideos(for: matchID)
    }

    nonisolated static func deleteVideos(for matchID: UUID) {
        for name in videoNames(for: matchID) {
            delete(named: name)
        }
        setVideoNames([], for: matchID)
    }

    nonisolated static func url(named name: String) -> URL? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    nonisolated static func delete(named name: String) {
        guard let url = url(named: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated private static var matchVideoMap: [String: [String]] {
        let rawMap = UserDefaults.standard.dictionary(forKey: matchVideoMapKey) ?? [:]
        var map: [String: [String]] = [:]

        for (matchID, value) in rawMap {
            if let names = value as? [String] {
                map[matchID] = names
            } else if let name = value as? String {
                map[matchID] = [name]
            }
        }

        return map
    }

    nonisolated private static func fileSize(for sourceURL: URL) throws -> Int64 {
        let resourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(max(1, resourceValues.fileSize ?? 1))
    }

    nonisolated private static func validateAvailableStorage(requiredFileSize fileSize: Int64) throws {
        let documentsValues = try URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let availableCapacity = documentsValues.volumeAvailableCapacityForImportantUsage else { return }
        let requiredCapacity = Int64(Double(fileSize) * 1.15) + 200_000_000
        if availableCapacity < requiredCapacity {
            throw VideoStorageError.insufficientStorage
        }
    }

    nonisolated private static func copyItem(
        from sourceURL: URL,
        to destinationURL: URL,
        totalBytes: Int64,
        progress: ((Double, Int64, Int64) -> Void)?
    ) throws {
        guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw VideoStorageError.copyFailed
        }

        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        let destinationHandle = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }

        var copiedBytes: Int64 = 0
        while true {
            guard let chunk = try sourceHandle.read(upToCount: copyBufferSize), !chunk.isEmpty else {
                break
            }
            try destinationHandle.write(contentsOf: chunk)
            copiedBytes += Int64(chunk.count)
            let fraction = min(1, Double(copiedBytes) / Double(max(1, totalBytes)))
            progress?(fraction, copiedBytes, totalBytes)
        }

        try destinationHandle.synchronize()
        progress?(1, totalBytes, totalBytes)
    }
}

enum VideoStorageError: Error {
    case insufficientStorage
    case copyFailed
}

extension Notification.Name {
    nonisolated static let videoStorageCopyProgress = Notification.Name("VideoStorageCopyProgress")
}
