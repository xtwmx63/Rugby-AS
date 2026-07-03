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
