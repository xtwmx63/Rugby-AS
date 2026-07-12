//
//  HighlightExporter.swift
//  Rugby AS
//
//  タイムラインで選んだ行(TRYなど)の場面を、1本の動画ファイルに
//  繋げて書き出すエンジン。
//
//  流れ:
//  1. タイムライン上の区間を「どの元動画の何秒目か」に変換する
//     (区間が複数の動画をまたぐ場合は自動で分割、動画のない区間はスキップ)
//  2. 変換した切れ端を順番に1本の動画へ合成する
//     (縦横の回転情報を補正し、サイズ違いは黒帯付きで収める)
//  3. mp4ファイルとして書き出す(進み具合を随時報告)
//

import AVFoundation
import Foundation

// 元動画ファイルの「どこから何秒」という切れ端
struct HighlightPiece {
    let url: URL
    let startSeconds: Double
    let durationSeconds: Double
}

enum HighlightExportError: LocalizedError {
    case noVideoForClips
    case compositionFailed
    case exportFailed(String?)

    var errorDescription: String? {
        switch self {
        case .noVideoForClips:
            return "この行のクリップに重なる動画がありません。"
        case .compositionFailed:
            return "動画の合成準備に失敗しました。"
        case .exportFailed(let detail):
            if let detail, !detail.isEmpty {
                return "書き出しに失敗しました(\(detail))。"
            }
            return "書き出しに失敗しました。空き容量を確認してもう一度試してください。"
        }
    }
}

enum HighlightExporter {
    // MARK: - 区間→元動画の切れ端への変換

    /// タイムライン上の区間リストを、元動画ファイルの切り出し位置に変換する。
    /// 戻り値: (切れ端のリスト, 動画がなくて丸ごとスキップした区間の数)
    static func resolvePieces(
        ranges: [(start: Double, end: Double)],
        videoSegments: [VideoSegment]
    ) -> (pieces: [HighlightPiece], skippedRanges: Int) {
        let playableSegments = videoSegments
            .filter { $0.fileName != nil }
            .sorted { $0.startTime < $1.startTime }

        var pieces: [HighlightPiece] = []
        var skippedRanges = 0

        for range in ranges {
            var isCovered = false
            for segment in playableSegments {
                let overlapStart = max(range.start, segment.startTime)
                let overlapEnd = min(range.end, segment.endTime)
                guard overlapEnd - overlapStart > 0.1,
                      let fileName = segment.fileName,
                      let url = VideoStorage.url(named: fileName) else {
                    continue
                }
                pieces.append(
                    HighlightPiece(
                        url: url,
                        startSeconds: overlapStart - segment.startTime,
                        durationSeconds: overlapEnd - overlapStart
                    )
                )
                isCovered = true
            }
            if !isCovered {
                skippedRanges += 1
            }
        }
        return (pieces, skippedRanges)
    }

    // MARK: - 合成と書き出し

    /// 切れ端を順番に繋げて1本のmp4に書き出す。完成したファイルのURLを返す。
    static func export(
        pieces: [HighlightPiece],
        fileName: String,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        guard !pieces.isEmpty else {
            throw HighlightExportError.noVideoForClips
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw HighlightExportError.compositionFailed
        }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero
        var renderSize = CGSize(width: 1920, height: 1080)
        var didDecideRenderSize = false
        var frameDuration = CMTime(value: 1, timescale: 30)

        for piece in pieces {
            let asset = AVURLAsset(url: piece.url)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                continue
            }
            let sourceAudio = try? await asset.loadTracks(withMediaType: .audio).first

            let timeRange = CMTimeRange(
                start: CMTime(seconds: piece.startSeconds, preferredTimescale: 600),
                duration: CMTime(seconds: piece.durationSeconds, preferredTimescale: 600)
            )

            do {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: cursor)
            } catch {
                // 壊れた切れ端は飛ばして続行(1つの不良で全体を失敗させない)
                continue
            }
            if let sourceAudio {
                try? audioTrack?.insertTimeRange(timeRange, of: sourceAudio, at: cursor)
            }

            // 回転情報(縦撮り等)を読み、見た目通りのサイズを求める
            let naturalSize = try await sourceVideo.load(.naturalSize)
            let preferredTransform = try await sourceVideo.load(.preferredTransform)
            let frameRate = try await sourceVideo.load(.nominalFrameRate)
            let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            let displaySize = CGSize(width: abs(displayRect.width), height: abs(displayRect.height))

            // 最初の切れ端のサイズ・フレームレートを出力の基準にする
            if !didDecideRenderSize, displaySize.width > 0, displaySize.height > 0 {
                renderSize = displaySize
                didDecideRenderSize = true
                if frameRate > 0 {
                    frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate.rounded())))
                }
            }

            // この切れ端の表示変換(回転補正+基準サイズに黒帯付きで収める)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: timeRange.duration)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(
                fittingTransform(
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform,
                    renderSize: renderSize
                ),
                at: cursor
            )
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)

            cursor = cursor + timeRange.duration
        }

        guard !instructions.isEmpty else {
            throw HighlightExportError.noVideoForClips
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        videoComposition.instructions = instructions

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw HighlightExportError.compositionFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        // 0.2秒ごとに進み具合を報告しながら書き出す
        let progressTask = Task {
            while !Task.isCancelled {
                let progress = Double(session.progress)
                await onProgress(progress)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { progressTask.cancel() }

        await withCheckedContinuation { continuation in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        guard session.status == .completed else {
            throw HighlightExportError.exportFailed(session.error?.localizedDescription)
        }
        await onProgress(1.0)
        return outputURL
    }

    // 回転補正した映像を、出力サイズの中央に「はみ出さず収まる」ように置く変換
    private static func fittingTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(displayRect.width), height: abs(displayRect.height))
        guard displaySize.width > 0, displaySize.height > 0 else { return preferredTransform }

        // 回転で負の座標に行った分を原点へ戻す
        var transform = preferredTransform
        transform.tx -= displayRect.minX
        transform.ty -= displayRect.minY

        // 出力サイズに収める縮尺と、中央寄せの移動
        let scale = min(renderSize.width / displaySize.width, renderSize.height / displaySize.height)
        let offsetX = (renderSize.width - displaySize.width * scale) / 2
        let offsetY = (renderSize.height - displaySize.height * scale) / 2

        return transform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}
