//
//  TimelineVideoPlayer.swift
//  Rugby AS
//
//  タイムライン編集画面の動画再生まわり。
//  AVPlayer（iOS標準の動画エンジン）の持ち方・シーク・時間監視を
//  ここに閉じ込めて、画面側は「何秒へ移動」「再生/停止」だけを扱う。
//

import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class TimelineVideoController {
    let player = AVPlayer()
    private var timeObserver: Any?
    private var loadedURL: URL?

    // 再生中に約1/30秒ごとに呼ばれる。引数は動画内の位置（秒）。
    var onTick: ((Double) -> Void)?

    func load(url: URL) {
        guard loadedURL != url else { return }
        loadedURL = url
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func unload() {
        pause()
        stopObserving()
        loadedURL = nil
        player.replaceCurrentItem(with: nil)
    }

    var durationSeconds: Double? {
        guard let duration = player.currentItem?.duration.seconds,
              duration.isFinite, duration > 0 else {
            return nil
        }
        return duration
    }

    var currentVideoSeconds: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    /// precise: true はコマ単位の正確なシーク（確定時用）、
    /// false は速さ優先のシーク（指でスクラブ中用）。
    func seek(toVideoSeconds seconds: Double, precise: Bool = true) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        if precise {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: time)
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func startObserving() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            guard time.seconds.isFinite else { return }
            MainActor.assumeIsolated {
                self?.onTick?(time.seconds)
            }
        }
    }

    func stopObserving() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }
}

// 動画と試合時間の「時間合わせ」シート。
// スライダーで動画をスクラブし（上のプレビューに映像が出る）、
// 「今の位置に設定」で前半/後半キックオフの動画内位置を確定する。
struct VideoAlignmentSheet: View {
    let controller: TimelineVideoController
    let firstHalfKickoff: Double?
    let secondHalfKickoff: Double?
    let onSetFirstHalf: (Double?) -> Void
    let onSetSecondHalf: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scrubSeconds: Double = 0
    @State private var durationSeconds: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("時間合わせ")
                    .font(.headline.weight(.black))
                Spacer()
                Button("完了") {
                    dismiss()
                }
                .font(.headline.weight(.bold))
            }

            Text("スライダーで動画を動かし、キックオフの瞬間で「今の位置に設定」を押してください。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Slider(value: $scrubSeconds, in: 0...max(durationSeconds, 1)) { isEditing in
                    if !isEditing {
                        controller.seek(toVideoSeconds: scrubSeconds)
                    }
                }
                .onChange(of: scrubSeconds) { _, newValue in
                    controller.seek(toVideoSeconds: newValue, precise: false)
                }

                HStack {
                    Text("動画位置 \(Self.timeText(scrubSeconds))")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Spacer()
                    HStack(spacing: 6) {
                        nudgeButton("-5", delta: -5)
                        nudgeButton("-1", delta: -1)
                        nudgeButton("+1", delta: 1)
                        nudgeButton("+5", delta: 5)
                    }
                }
            }

            kickoffRow(
                title: "前半キックオフ",
                value: firstHalfKickoff,
                onSet: onSetFirstHalf
            )
            kickoffRow(
                title: "後半キックオフ",
                value: secondHalfKickoff,
                onSet: onSetSecondHalf
            )

            Spacer(minLength: 0)
        }
        .padding(18)
        .onAppear {
            controller.pause()
            durationSeconds = controller.durationSeconds ?? 1
            scrubSeconds = min(controller.currentVideoSeconds, durationSeconds)
        }
    }

    private func kickoffRow(
        title: String,
        value: Double?,
        onSet: @escaping (Double?) -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(value.map { "動画の \(Self.timeText($0))" } ?? "未設定")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(value == nil ? .secondary : .primary)
            }

            Spacer()

            if value != nil {
                Button("解除") {
                    onSet(nil)
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.bordered)
            }

            Button("今の位置に設定") {
                onSet(scrubSeconds)
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func nudgeButton(_ title: String, delta: Double) -> some View {
        Button(title) {
            scrubSeconds = min(max(0, scrubSeconds + delta), durationSeconds)
            controller.seek(toVideoSeconds: scrubSeconds)
        }
        .font(.caption.weight(.bold).monospacedDigit())
        .buttonStyle(.bordered)
    }

    private static func timeText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// 動画の映像だけを表示する面（標準の再生ボタン等は出さない。
// 操作はタイムライン側の再生ボタン・スクラブで行うため）。
struct VideoSurfaceView: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}
