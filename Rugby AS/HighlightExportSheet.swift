//
//  HighlightExportSheet.swift
//  Rugby AS
//
//  タイムラインの行(TRY・HOMEなど)を選ぶと、その行のクリップ場面を
//  1本のハイライト動画に繋げて書き出すシート。
//  書き出し中は進み具合を表示し、完成したら共有ボタンを出す。
//

import SwiftUI

struct HighlightExportSheet: View {
    let clips: [TimelineClip]
    let videoSegments: [VideoSegment]

    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case pickTrack
        case exporting(Double)
        case done(URL, skippedRanges: Int)
        case failed(String)
    }

    @State private var phase: Phase = .pickTrack

    // ハイライトにできる行(場面を持つトラックだけ)
    private var exportableTracks: [TimelineTrackType] {
        TimelineTrackType.timelineTracks.filter(\.supportsSequentialPlayback)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pickTrack:
                    trackPickerList
                case .exporting(let progress):
                    exportingView(progress: progress)
                case .done(let url, let skippedRanges):
                    doneView(url: url, skippedRanges: skippedRanges)
                case .failed(let message):
                    failedView(message: message)
                }
            }
            .navigationTitle("ハイライト動画")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .disabled(isExporting)
                }
            }
        }
        .interactiveDismissDisabled(isExporting)
    }

    private var isExporting: Bool {
        if case .exporting = phase { return true }
        return false
    }

    // MARK: - 行の選択

    private var trackPickerList: some View {
        List {
            Section {
                ForEach(exportableTracks) { track in
                    trackRow(track)
                }
            } footer: {
                Text("選んだ行のクリップ場面を時系列に繋げて、1本の動画として書き出します。動画が置かれていない場面はスキップされます。")
            }
        }
    }

    private func trackRow(_ track: TimelineTrackType) -> some View {
        let ranges = mergedRanges(for: track)
        let totalSeconds = ranges.reduce(0.0) { $0 + ($1.end - $1.start) }
        let (pieces, _) = HighlightExporter.resolvePieces(ranges: ranges, videoSegments: videoSegments)
        let isExportable = !pieces.isEmpty

        return Button {
            startExport(track: track, ranges: ranges)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: track.systemImage)
                    .font(.headline)
                    .foregroundStyle(track.color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isExportable ? Color.primary : Color.secondary)
                    Text("\(ranges.count)場面・約\(timeText(totalSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "film")
                    .foregroundStyle(isExportable ? Color.accentColor : Color.secondary.opacity(0.4))
            }
        }
        .disabled(!isExportable)
    }

    // MARK: - 書き出し中/完了/失敗

    private func exportingView(progress: Double) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .padding(.horizontal, 32)
            Text("書き出し中… \(Int(progress * 100))%")
                .font(.headline.monospacedDigit())
            Text("動画の長さによって数分かかることがあります。\nこの画面を閉じずにお待ちください。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneView(url: URL, skippedRanges: Int) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("ハイライト動画ができました")
                .font(.headline)

            if skippedRanges > 0 {
                Text("動画が置かれていない\(skippedRanges)場面はスキップしました。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            ShareLink(item: url) {
                Label("動画を共有・保存", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)

            Button("別の行を書き出す") {
                phase = .pickTrack
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("戻る") {
                phase = .pickTrack
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 書き出しの実行

    private func startExport(track: TimelineTrackType, ranges: [(start: Double, end: Double)]) {
        let (pieces, skippedRanges) = HighlightExporter.resolvePieces(
            ranges: ranges,
            videoSegments: videoSegments
        )
        guard !pieces.isEmpty else {
            phase = .failed(HighlightExportError.noVideoForClips.errorDescription ?? "書き出せる場面がありません。")
            return
        }

        phase = .exporting(0)
        let fileName = "\(track.title)_highlight_\(Self.fileDateFormatter.string(from: Date())).mp4"

        Task {
            do {
                let url = try await HighlightExporter.export(
                    pieces: pieces,
                    fileName: fileName,
                    onProgress: { progress in
                        if case .exporting = phase {
                            phase = .exporting(progress)
                        }
                    }
                )
                phase = .done(url, skippedRanges: skippedRanges)
            } catch {
                phase = .failed((error as? HighlightExportError)?.errorDescription
                    ?? "書き出しに失敗しました。もう一度試してください。")
            }
        }
    }

    // その行のクリップを時系列に並べ、重なる区間は1つにまとめる
    // (連続再生と同じルール。ハイライトの中身と再生順が一致する)
    private func mergedRanges(for track: TimelineTrackType) -> [(start: Double, end: Double)] {
        let trackClips = clips
            .filter { $0.trackType == track && $0.endTime > $0.startTime }
            .sorted { $0.startTime < $1.startTime }

        var merged: [(start: Double, end: Double)] = []
        for clip in trackClips {
            if let last = merged.last, clip.startTime <= last.end + 0.5 {
                merged[merged.count - 1].end = max(last.end, clip.endTime)
            } else {
                merged.append((clip.startTime, clip.endTime))
            }
        }
        return merged
    }

    private func timeText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return formatter
    }()
}
