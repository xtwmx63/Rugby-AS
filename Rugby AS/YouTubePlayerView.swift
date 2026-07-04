//
//  YouTubePlayerView.swift
//  Rugby AS
//
//  YouTube公式の埋め込みプレーヤー(iframe API)をアプリ内に表示する部品。
//  動画ファイルを端末に持たず、URLと開始/終了タイムだけで試合映像を扱える。
//  ダウンロードはYouTube規約違反かつ壊れやすいので行わず、正規の埋め込みのみ使う。
//
//  仕組み: WKWebView(アプリ内ブラウザ)に小さなHTMLを読み込み、
//  JavaScriptのプレーヤーへ「再生」「停止」「◯秒へ移動」を指示する。
//  再生位置は0.25秒ごとに問い合わせて、タイムラインへ反映する。
//

import Foundation
import SwiftUI
import WebKit

@MainActor
final class YouTubePlayerController: NSObject {
    let webView: WKWebView
    private(set) var loadedVideoID: String?
    private var isPlayerReady = false
    private var pendingCommands: [String] = []
    private var pollTimer: Timer?

    // 再生中に約0.25秒ごとに呼ばれる。引数はYouTube動画内の位置(秒)。
    var onTick: ((Double) -> Void)?
    // 動画そのものが最後まで再生されたときに呼ばれる。
    var onEnded: (() -> Void)?
    // プレーヤーがエラーを出したときに呼ばれる。引数はYouTubeのエラーコード。
    var onError: ((Int) -> Void)?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        super.init()
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: "yt")
    }

    func load(videoID: String, startSeconds: Double) {
        if loadedVideoID == videoID {
            seek(to: startSeconds)
            return
        }
        loadedVideoID = videoID
        isPlayerReady = false
        pendingCommands = []
        webView.loadHTMLString(
            Self.playerHTML(videoID: videoID, startSeconds: Int(max(0, startSeconds))),
            baseURL: URL(string: Self.embedOrigin)
        )
    }

    func play() {
        run("player.playVideo();")
        startPolling()
    }

    func pause() {
        run("player.pauseVideo();")
        stopPolling()
    }

    func seek(to seconds: Double) {
        run("player.seekTo(\(max(0, seconds)), true);")
    }

    func unload() {
        pause()
        loadedVideoID = nil
        isPlayerReady = false
        pendingCommands = []
        webView.loadHTMLString("", baseURL: nil)
    }

    // プレーヤー準備前に来た指示は貯めておき、準備完了後にまとめて流す
    private func run(_ javaScript: String) {
        guard isPlayerReady else {
            pendingCommands.append(javaScript)
            return
        }
        webView.evaluateJavaScript(javaScript, completionHandler: nil)
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollCurrentTime()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollCurrentTime() {
        guard isPlayerReady else { return }
        webView.evaluateJavaScript("player.getCurrentTime()") { [weak self] result, _ in
            guard let seconds = result as? Double, seconds.isFinite else { return }
            MainActor.assumeIsolated {
                self?.onTick?(seconds)
            }
        }
    }

    fileprivate func handleMessage(_ body: String?) {
        guard let body else { return }
        if body == "ready" {
            isPlayerReady = true
            let commands = pendingCommands
            pendingCommands = []
            for command in commands {
                webView.evaluateJavaScript(command, completionHandler: nil)
            }
        } else if body == "state:0" {
            // 0 = 再生終了
            stopPolling()
            onEnded?()
        } else if body.hasPrefix("error:") {
            stopPolling()
            let code = Int(body.dropFirst("error:".count)) ?? -1
            onError?(code)
        }
    }

    /// YouTubeのエラーコードを人に分かる説明にする
    static func errorDescription(forCode code: Int) -> String {
        switch code {
        case 2:
            return "動画IDが正しくありません。URLを確認してください。"
        case 5:
            return "この動画はアプリ内プレーヤーで再生できませんでした。"
        case 100:
            return "動画が見つかりません(削除済みか非公開の可能性)。"
        case 101, 150, 152, 153:
            return "この動画は投稿者が埋め込み再生を許可していないため、アプリ内では再生できません。"
        default:
            return "YouTube動画を再生できませんでした(コード\(code))。通信環境を確認してください。"
        }
    }

    // 埋め込み元として名乗るアドレス。YouTubeの新しいプレーヤーは
    // 素性(origin)が不明な埋め込みを弾くことがある(エラー152等)ため必須。
    static let embedOrigin = "https://www.youtube.com"

    private static func playerHTML(videoID: String, startSeconds: Int) -> String {
        // 枠(iframe)を自分で置き、src に本物の埋め込みアドレスを直接指定する。
        // API に枠を作らせるとアプリ内では素性がずれて弾かれる(エラー150/152)ため、
        // 既にある枠に YT.Player を後付けする方式にする。
        let embedURL = "https://www.youtube.com/embed/\(videoID)"
            + "?enablejsapi=1&playsinline=1&controls=0&rel=0&fs=0&iv_load_policy=3"
            + "&start=\(startSeconds)&origin=\(embedOrigin)"
        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#player{width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe id="player" src="\(embedURL)" width="100%" height="100%"
          frameborder="0" allow="autoplay; encrypted-media; fullscreen"></iframe>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            events: {
              onReady: function() { window.webkit.messageHandlers.yt.postMessage('ready'); },
              onStateChange: function(e) { window.webkit.messageHandlers.yt.postMessage('state:' + e.data); },
              onError: function(e) { window.webkit.messageHandlers.yt.postMessage('error:' + e.data); }
            }
          });
        }
        </script></body></html>
        """
    }
}

extension YouTubePlayerController: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body as? String
        Task { @MainActor in
            self.handleMessage(body)
        }
    }
}

// WKWebViewはハンドラを強く保持するため、そのまま渡すとメモリが解放されなくなる。
// 弱い参照で包んで渡すための小さな中継役。
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// YouTubeの映像面を表示するSwiftUI部品
struct YouTubePlayerSurfaceView: UIViewRepresentable {
    let controller: YouTubePlayerController

    func makeUIView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// YouTubeのURLと開始/終了タイムを入力するシート
struct YouTubeVideoAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var startText = ""
    @State private var endText = ""
    @State private var validationMessage: String?

    // (動画ID, 開始秒, 終了秒) を返す
    let onAdd: (String, Double, Double) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://youtu.be/...", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("YouTubeのURL")
                }

                Section {
                    HStack {
                        Text("開始")
                        Spacer()
                        TextField("例 12:30", text: $startText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("終了")
                        Spacer()
                        TextField("例 55:00", text: $endText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("使う区間")
                } footer: {
                    Text("「分:秒」または「時:分:秒」で入力。YouTube動画のこの区間だけをタイムラインに置きます。再生にはネット接続が必要です。")
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("タイムラインに追加") {
                        submit()
                    }
                    .font(.headline)
                }
            }
            .navigationTitle("YouTubeから追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func submit() {
        guard let videoID = YouTubeVideoStorage.videoID(fromURL: urlText) else {
            validationMessage = "URLからYouTube動画を見つけられませんでした。動画ページのURLを貼り付けてください。"
            return
        }
        guard let start = YouTubeVideoStorage.seconds(fromTimeText: startText),
              let end = YouTubeVideoStorage.seconds(fromTimeText: endText),
              end > start else {
            validationMessage = "開始・終了タイムを確認してください(終了は開始より後)。"
            return
        }
        onAdd(videoID, start, end)
        dismiss()
    }
}

// 試合ごとのYouTube動画情報(動画ID・開始/終了タイム)の保存。
// 動画ファイルは持たないので、この3つの情報だけ端末設定に残す。
struct StoredYouTubeVideo: Codable, Equatable {
    var videoID: String
    var startSeconds: Double
    var endSeconds: Double
}

enum YouTubeVideoStorage {
    private static let storageKey = "youtubeVideosByMatchID"

    static func videos(for matchID: UUID) -> [StoredYouTubeVideo] {
        allVideos()[matchID.uuidString] ?? []
    }

    static func setVideos(_ videos: [StoredYouTubeVideo], for matchID: UUID) {
        var all = allVideos()
        if videos.isEmpty {
            all.removeValue(forKey: matchID.uuidString)
        } else {
            all[matchID.uuidString] = videos
        }
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func allVideos() -> [String: [StoredYouTubeVideo]] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [StoredYouTubeVideo]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    /// YouTubeのURL文字列から動画IDを取り出す。対応形式:
    /// youtu.be/ID, youtube.com/watch?v=ID, /shorts/ID, /live/ID, /embed/ID
    static func videoID(fromURL urlText: String) -> String? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        let host = (url.host ?? "").lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        var candidate: String?
        if host.contains("youtu.be") {
            candidate = pathComponents.first
        } else if host.contains("youtube.com") {
            if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let v = query.first(where: { $0.name == "v" })?.value {
                candidate = v
            } else if let markerIndex = pathComponents.firstIndex(where: { ["shorts", "live", "embed"].contains($0) }),
                      markerIndex + 1 < pathComponents.count {
                candidate = pathComponents[markerIndex + 1]
            }
        }

        guard let candidate,
              candidate.count >= 6,
              candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            return nil
        }
        return candidate
    }

    /// "1:23:45"・"12:30"・"45" のような時間表記を秒に変換する。不正なら nil。
    static func seconds(fromTimeText text: String) -> Double? {
        let parts = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
            .map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }

        var total: Double = 0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }
}
