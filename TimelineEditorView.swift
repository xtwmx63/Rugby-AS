//
//  TimelineEditorView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/29.
//

import AVFoundation
import Combine
import CoreTransferable
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum TimelineTrackType: String, CaseIterable, Identifiable, Hashable {
    case video
    case match
    case home
    case away
    case bip
    case tryEvent
    case conv
    case pg
    case dg
    case lo
    case scr
    case deleteTool

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return "VIDEO"
        case .match: return "MATCH"
        case .home: return "HOME"
        case .away: return "AWAY"
        case .bip: return "BIP"
        case .tryEvent: return "TRY"
        case .conv: return "CONV"
        case .pg: return "PG"
        case .dg: return "DG"
        case .lo: return "LO"
        case .scr: return "SCR"
        case .deleteTool: return "DELETE"
        }
    }

    var systemImage: String {
        switch self {
        case .video: return "film.stack.fill"
        case .match: return "timer"
        case .home: return "house.fill"
        case .away: return "a.circle.fill"
        case .bip: return "j.circle.fill"
        case .tryEvent: return "rugbyball.fill"
        case .conv: return "figure.rugby"
        case .pg: return "p.circle.fill"
        case .dg: return "d.circle.fill"
        case .lo: return "arrow.up.and.down.and.sparkles"
        case .scr: return "person.3.fill"
        case .deleteTool: return "trash.fill"
        }
    }

    var color: Color {
        switch self {
        case .video: return Color(red: 0.55, green: 0.30, blue: 0.95)
        case .match: return Color(red: 0.16, green: 0.78, blue: 0.55)
        case .home: return Color(red: 0.02, green: 0.35, blue: 0.96)
        case .away: return Color(red: 0.96, green: 0.10, blue: 0.18)
        case .bip: return Color(red: 0.38, green: 0.16, blue: 0.88)
        case .tryEvent: return Color(red: 0.20, green: 0.72, blue: 0.22)
        case .conv: return Color(red: 0.06, green: 0.66, blue: 0.76)
        case .pg: return Color(red: 0.94, green: 0.72, blue: 0.10)
        case .dg: return Color(red: 0.96, green: 0.60, blue: 0.08)
        case .lo: return Color(red: 0.06, green: 0.72, blue: 0.82)
        case .scr: return Color(red: 0.92, green: 0.36, blue: 0.06)
        case .deleteTool: return Color(red: 0.86, green: 0.12, blue: 0.18)
        }
    }

    var isTimelineTrack: Bool {
        self != .deleteTool
    }

    // 左のラベルをタップして「その行のクリップだけを連続再生」できる行。
    // VIDEO/MATCH は場面の行ではないので対象外。
    var supportsSequentialPlayback: Bool {
        switch self {
        case .home, .away, .bip, .tryEvent, .conv, .pg, .dg, .lo, .scr:
            return true
        case .video, .match, .deleteTool:
            return false
        }
    }

    static let timelineTracks: [TimelineTrackType] = [
        .video, .match, .home, .away, .bip, .tryEvent, .conv, .pg, .dg, .lo, .scr
    ]

    static let toolPalette: [TimelineTrackType] = [
        .home, .away, .bip, .tryEvent, .conv, .pg, .dg, .lo, .scr, .deleteTool
    ]
}

struct TimelineClip: Identifiable, Equatable {
    let id: UUID
    var trackType: TimelineTrackType
    var startTime: Double
    var endTime: Double
    var title: String
    var isSelected: Bool

    var color: Color { trackType.color }
}

enum MatchHalfType: String, Codable {
    case first
    case second

    var title: String {
        switch self {
        case .first: return "前半"
        case .second: return "後半"
        }
    }
}

struct MatchSegment: Identifiable, Equatable {
    let id: UUID
    var halfType: MatchHalfType
    var startTime: Double
    var endTime: Double
    var displayLabel: String
}

struct VideoSegment: Identifiable, Equatable {
    let id: UUID
    var sourceName: String
    var startTime: Double
    var endTime: Double
    var fileName: String? = nil
}

struct TimelineState {
    var timelineClips: [TimelineClip]
    var matchSegments: [MatchSegment]
    var videoSegments: [VideoSegment]
    var selectedClipID: UUID?
    var selectedVideoSegmentID: UUID?
}

@MainActor
final class TimelineEditorViewModel: ObservableObject {
    @Published var currentVideoTime: Double
    @Published var videoDuration: Double
    @Published var selectedTool: TimelineTrackType
    @Published var selectedClipID: UUID?
    @Published var visibleTracks: [TimelineTrackType]
    @Published var timelineClips: [TimelineClip]
    @Published var matchSegments: [MatchSegment]
    @Published var videoSegments: [VideoSegment]
    @Published var undoStack: [TimelineState]
    @Published var redoStack: [TimelineState]
    @Published var isPlaying: Bool
    @Published var selectedVideoSegmentID: UUID?

    init(
        currentVideoTime: Double,
        videoDuration: Double,
        selectedTool: TimelineTrackType,
        selectedClipID: UUID?,
        visibleTracks: [TimelineTrackType],
        timelineClips: [TimelineClip],
        matchSegments: [MatchSegment],
        videoSegments: [VideoSegment],
        undoStack: [TimelineState] = [],
        redoStack: [TimelineState] = [],
        isPlaying: Bool = false,
        selectedVideoSegmentID: UUID? = nil
    ) {
        self.currentVideoTime = currentVideoTime
        self.videoDuration = videoDuration
        self.selectedTool = selectedTool
        self.selectedClipID = selectedClipID
        self.visibleTracks = visibleTracks
        self.timelineClips = timelineClips
        self.matchSegments = matchSegments
        self.videoSegments = videoSegments
        self.undoStack = undoStack
        self.redoStack = redoStack
        self.isPlaying = isPlaying
        self.selectedVideoSegmentID = selectedVideoSegmentID
    }

    static func empty() -> TimelineEditorViewModel {
        TimelineEditorViewModel(
            currentVideoTime: 0,
            videoDuration: 16 * 60,
            selectedTool: .home,
            selectedClipID: nil,
            visibleTracks: TimelineTrackType.timelineTracks,
            timelineClips: [],
            matchSegments: [],
            videoSegments: []
        )
    }

    static func mock() -> TimelineEditorViewModel {
        let selectedClipID = UUID()
        return TimelineEditorViewModel(
            currentVideoTime: 335.9,
            videoDuration: 16 * 60,
            selectedTool: .home,
            selectedClipID: selectedClipID,
            visibleTracks: TimelineTrackType.timelineTracks,
            timelineClips: [
                TimelineClip(id: selectedClipID, trackType: .home, startTime: 8, endTime: 318, title: "HOME", isSelected: true),
                TimelineClip(id: UUID(), trackType: .home, startTime: 342, endTime: 408, title: "HOME", isSelected: false),
                TimelineClip(id: UUID(), trackType: .home, startTime: 535, endTime: 604, title: "HOME", isSelected: false),
                TimelineClip(id: UUID(), trackType: .away, startTime: 18, endTime: 92, title: "AWAY", isSelected: false),
                TimelineClip(id: UUID(), trackType: .away, startTime: 316, endTime: 397, title: "AWAY", isSelected: false),
                TimelineClip(id: UUID(), trackType: .away, startTime: 412, endTime: 604, title: "AWAY", isSelected: false),
                TimelineClip(id: UUID(), trackType: .bip, startTime: 54, endTime: 152, title: "BIP", isSelected: false),
                TimelineClip(id: UUID(), trackType: .bip, startTime: 546, endTime: 648, title: "BIP", isSelected: false),
                TimelineClip(id: UUID(), trackType: .tryEvent, startTime: 454, endTime: 482, title: "TRY", isSelected: false),
                TimelineClip(id: UUID(), trackType: .tryEvent, startTime: 826, endTime: 852, title: "TRY", isSelected: false),
                TimelineClip(id: UUID(), trackType: .conv, startTime: 491, endTime: 516, title: "CONV", isSelected: false),
                TimelineClip(id: UUID(), trackType: .lo, startTime: 116, endTime: 150, title: "LO", isSelected: false),
                TimelineClip(id: UUID(), trackType: .lo, startTime: 698, endTime: 735, title: "LO", isSelected: false),
                TimelineClip(id: UUID(), trackType: .scr, startTime: 238, endTime: 286, title: "SCR", isSelected: false),
                TimelineClip(id: UUID(), trackType: .scr, startTime: 760, endTime: 812, title: "SCR", isSelected: false)
            ],
            matchSegments: [
                MatchSegment(id: UUID(), halfType: .first, startTime: 22, endTime: 442, displayLabel: "07:00\n(前半)"),
                MatchSegment(id: UUID(), halfType: .second, startTime: 568, endTime: 958, displayLabel: "~09:00\n(後半)")
            ],
            videoSegments: [
                VideoSegment(id: UUID(), sourceName: "V1", startTime: 0, endTime: 320),
                VideoSegment(id: UUID(), sourceName: "V2", startTime: 372, endTime: 960)
            ],
            undoStack: [],
            redoStack: []
        )
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func togglePlayback() {
        isPlaying.toggle()
    }

    func selectTool(_ tool: TimelineTrackType) {
        selectedTool = tool
        if tool == .deleteTool {
            deleteSelectedClip()
        }
    }

    func activateTool(_ tool: TimelineTrackType) {
        selectedTool = tool
        if tool == .deleteTool {
            deleteSelectedClip()
        } else {
            addClip(on: tool)
        }
    }

    func selectClip(_ id: UUID?) {
        selectedClipID = id
        if id != nil {
            selectedVideoSegmentID = nil
        }
        timelineClips = timelineClips.map { clip in
            var updated = clip
            updated.isSelected = clip.id == id
            return updated
        }
    }

    func selectVideoSegment(_ id: UUID?) {
        selectedVideoSegmentID = id
        if id != nil {
            selectClip(nil)
        }
    }

    func setTimelineClips(_ clips: [TimelineClip]) {
        selectedClipID = selectedClipID.flatMap { id in
            clips.contains(where: { $0.id == id }) ? id : nil
        }
        timelineClips = clips.map { clip in
            var updated = clip
            updated.isSelected = clip.id == selectedClipID
            return updated
        }
    }

    func appendPersistedClip(_ clip: TimelineClip) {
        saveForUndo()
        var selectedClip = clip
        selectedClip.isSelected = true
        timelineClips.append(selectedClip)
        selectClip(selectedClip.id)
    }

    func setMatchSegments(_ segments: [MatchSegment]) {
        matchSegments = segments
    }

    func addClip(on trackType: TimelineTrackType) {
        guard trackType.isTimelineTrack, trackType != .video, trackType != .match else { return }
        saveForUndo()

        let length = defaultClipLength(for: trackType)
        let start = min(max(0, currentVideoTime), videoDuration - 1)
        let end = min(videoDuration, start + length)
        let clip = TimelineClip(
            id: UUID(),
            trackType: trackType,
            startTime: start,
            endTime: end,
            title: trackType.title,
            isSelected: true
        )
        timelineClips.append(clip)
        selectClip(clip.id)
    }

    @discardableResult
    func addVideoSegment(sourceName: String, duration: Double, fileName: String? = nil) -> VideoSegment {
        saveForUndo()
        let start = videoSegments.map(\.endTime).max().map { $0 + 12 } ?? 0
        let end = start + max(1, duration)
        let segment = VideoSegment(
            id: UUID(),
            sourceName: sourceName,
            startTime: start,
            endTime: end,
            fileName: fileName
        )
        videoSegments.append(segment)
        selectVideoSegment(segment.id)
        videoDuration = max(videoDuration, end)
        return segment
    }

    func setVideoSegments(_ segments: [VideoSegment]) {
        videoSegments = segments
        selectedVideoSegmentID = selectedVideoSegmentID.flatMap { id in
            segments.contains(where: { $0.id == id }) ? id : nil
        } ?? segments.first?.id
        if let maxEndTime = segments.map(\.endTime).max() {
            videoDuration = max(16 * 60, maxEndTime)
            currentVideoTime = min(currentVideoTime, videoDuration)
        }
    }

    func deleteSelectedVideoSegment() -> VideoSegment? {
        guard let selectedVideoSegmentID,
              let index = videoSegments.firstIndex(where: { $0.id == selectedVideoSegmentID }) else { return nil }
        saveForUndo()
        let removed = videoSegments.remove(at: index)
        self.selectedVideoSegmentID = videoSegments.first?.id
        videoDuration = max(16 * 60, videoSegments.map(\.endTime).max() ?? 16 * 60)
        return removed
    }

    func videoSegment(id: UUID?) -> VideoSegment? {
        guard let id else { return nil }
        return videoSegments.first { $0.id == id }
    }

    func clip(id: UUID?) -> TimelineClip? {
        guard let id else { return nil }
        return timelineClips.first { $0.id == id }
    }

    func deleteSelectedClip() {
        guard let selectedClipID,
              timelineClips.contains(where: { $0.id == selectedClipID }) else { return }
        saveForUndo()
        timelineClips.removeAll { $0.id == selectedClipID }
        self.selectedClipID = nil
    }

    @discardableResult
    func adjustSelectedClipStart(by delta: Double) -> Bool {
        guard let selectedClipID,
              let index = timelineClips.firstIndex(where: { $0.id == selectedClipID }) else { return false }
        let newStart = min(max(0, timelineClips[index].startTime + delta), timelineClips[index].endTime - 1)
        guard abs(newStart - timelineClips[index].startTime) > 0.001 else { return false }
        saveForUndo()
        timelineClips[index].startTime = newStart
        return true
    }

    @discardableResult
    func adjustSelectedClipEnd(by delta: Double) -> Bool {
        guard let selectedClipID,
              let index = timelineClips.firstIndex(where: { $0.id == selectedClipID }) else { return false }
        let newEnd = max(min(videoDuration, timelineClips[index].endTime + delta), timelineClips[index].startTime + 1)
        guard abs(newEnd - timelineClips[index].endTime) > 0.001 else { return false }
        saveForUndo()
        timelineClips[index].endTime = newEnd
        return true
    }

    // 選択中のクリップを、長さを保ったまま左右へ動かす
    @discardableResult
    func moveSelectedClip(by delta: Double) -> Bool {
        guard let selectedClipID,
              let index = timelineClips.firstIndex(where: { $0.id == selectedClipID }) else { return false }
        let length = timelineClips[index].endTime - timelineClips[index].startTime
        let newStart = min(max(0, timelineClips[index].startTime + delta), max(0, videoDuration - length))
        guard abs(newStart - timelineClips[index].startTime) > 0.001 else { return false }
        saveForUndo()
        timelineClips[index].startTime = newStart
        timelineClips[index].endTime = newStart + length
        return true
    }

    @discardableResult
    func adjustSelectedClipStart(to newStart: Double) -> Bool {
        guard let selectedClipID,
              let index = timelineClips.firstIndex(where: { $0.id == selectedClipID }) else { return false }
        let clampedStart = min(max(0, newStart), timelineClips[index].endTime - 1)
        guard abs(clampedStart - timelineClips[index].startTime) > 0.001 else { return false }
        saveForUndo()
        timelineClips[index].startTime = clampedStart
        return true
    }

    @discardableResult
    func adjustSelectedClipEnd(to newEnd: Double) -> Bool {
        guard let selectedClipID,
              let index = timelineClips.firstIndex(where: { $0.id == selectedClipID }) else { return false }
        let clampedEnd = max(min(videoDuration, newEnd), timelineClips[index].startTime + 1)
        guard abs(clampedEnd - timelineClips[index].endTime) > 0.001 else { return false }
        saveForUndo()
        timelineClips[index].endTime = clampedEnd
        return true
    }

    func undo() {
        guard let previousState = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(previousState)
    }

    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(nextState)
    }

    var currentState: TimelineState {
        snapshot()
    }

    private func saveForUndo() {
        undoStack.append(snapshot())
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    private func snapshot() -> TimelineState {
        TimelineState(
            timelineClips: timelineClips,
            matchSegments: matchSegments,
            videoSegments: videoSegments,
            selectedClipID: selectedClipID,
            selectedVideoSegmentID: selectedVideoSegmentID
        )
    }

    private func restore(_ state: TimelineState) {
        timelineClips = state.timelineClips
        matchSegments = state.matchSegments
        videoSegments = state.videoSegments
        selectedVideoSegmentID = state.selectedVideoSegmentID
        selectClip(state.selectedClipID)
        if state.selectedVideoSegmentID != nil {
            selectedVideoSegmentID = state.selectedVideoSegmentID
        }
    }

    private func defaultClipLength(for trackType: TimelineTrackType) -> Double {
        switch trackType {
        case .tryEvent, .conv, .pg, .dg, .lo, .scr:
            return 26
        default:
            return 58
        }
    }
}

struct TimelineEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TimelineEditorViewModel
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var isVideoImporting = false
    @State private var videoImportProgress: Double = 0
    @State private var editorErrorMessage: String?
    @State private var didLoadStoredVideos = false
    @State private var didLoadStoredEvents = false
    @State private var videoPlayer: AVPlayer?
    @State private var activeVideoSegmentID: UUID?
    @State private var playbackTimeObserver: Any?
    @State private var videoEndObserver: NSObjectProtocol?
    @State private var isScrubbingTimeline = false
    // スクラブ(指でのシーク)中は、動画へのシーク要求を間引いて軽くする
    @State private var pendingScrubSeekTime: Double?
    @State private var isScrubSeekInFlight = false
    @State private var isMatchClockSettingsPresented = false
    @State private var isHighlightExportPresented = false
    @State private var matchClockSettings: TimelineMatchClockSettings = .standard
    // トラック連続再生: 選択中の行と、再生する区間のリスト・現在位置
    @State private var selectedPlaybackTrack: TimelineTrackType?
    @State private var playbackQueue: [(start: Double, end: Double)] = []
    @State private var playbackQueueIndex = 0

    let match: Match?

    init(match: Match? = nil) {
        self.match = match
        _viewModel = StateObject(wrappedValue: TimelineEditorViewModel.empty())
    }

    init(match: Match? = nil, viewModel: TimelineEditorViewModel) {
        self.match = match
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        GeometryReader { proxy in
            let topPadding = max(58, min(proxy.safeAreaInsets.top + 10, 86))
            let bottomPadding = max(proxy.safeAreaInsets.bottom, 8)
            let availableHeight = max(0, proxy.size.height - topPadding - bottomPadding)
            let verticalSpacing: CGFloat = 40
            let fixedHeight: CGFloat = 54 + 58 + 98 + verticalSpacing
            let minimumTimelineHeight: CGFloat = 42 + (48 * 4)
            let widthBasedVideoHeight = proxy.size.width * 0.58
            let heightBasedVideoHeight = availableHeight * 0.38
            let videoHeight = min(max(min(widthBasedVideoHeight, heightBasedVideoHeight), 230), 350)
            let timelineHeight = max(minimumTimelineHeight, availableHeight - fixedHeight - videoHeight)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.00, green: 0.02, blue: 0.06),
                        Color(red: 0.02, green: 0.09, blue: 0.18),
                        Color(red: 0.00, green: 0.16, blue: 0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 10) {
                    TimelineHeaderView(
                        onBack: { dismiss() },
                        onExport: {
                            // 書き出し中に映像が動いていると紛らわしいので止める
                            videoPlayer?.pause()
                            viewModel.isPlaying = false
                            isHighlightExportPresented = true
                        }
                    )

                    VideoPreviewCard(
                        videoSegments: viewModel.videoSegments,
                        player: videoPlayer,
                        selectedVideoSegmentID: viewModel.selectedVideoSegmentID
                    )
                        .frame(height: videoHeight)
                        .overlay(alignment: .topTrailing) {
                            PhotosPicker(selection: $selectedVideoItems, maxSelectionCount: 8, matching: .videos) {
                                Label("動画追加", systemImage: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.44))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.26), lineWidth: 1)
                                    )
                            }
                            .disabled(isVideoImporting)
                            .padding(12)
                        }
                        .overlay(alignment: .bottomLeading) {
                            if isVideoImporting {
                                HStack(spacing: 8) {
                                    ProgressView(value: videoImportProgress)
                                        .progressViewStyle(.linear)
                                        .frame(width: 112)
                                    Text("読み込み中")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.black.opacity(0.46)))
                                .padding(12)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if viewModel.selectedVideoSegmentID != nil {
                                Button(role: .destructive) {
                                    deleteSelectedTimelineItem()
                                } label: {
                                    Label("動画削除", systemImage: "trash.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(Color.red.opacity(0.78)))
                                }
                                .padding(12)
                            }
                        }

                    PlaybackControlBar(
                        currentVideoTime: viewModel.currentVideoTime,
                        videoDuration: viewModel.videoDuration,
                        isPlaying: viewModel.isPlaying,
                        canUndo: viewModel.canUndo,
                        canRedo: viewModel.canRedo,
                        onPlayPause: { toggleVideoPlayback() },
                        onUndo: {
                            viewModel.undo()
                            persistTimelineStateToStorage()
                            configurePlayerForSelectedVideo(autoplay: false)
                        },
                        onRedo: {
                            viewModel.redo()
                            persistTimelineStateToStorage()
                            configurePlayerForSelectedVideo(autoplay: false)
                        }
                    )

                    TimelineTracksView(
                        viewModel: viewModel,
                        isScrubbingTimeline: $isScrubbingTimeline,
                        selectedPlaybackTrack: selectedPlaybackTrack,
                        onSelectVideoSegment: { segment in
                            selectVideoSegment(segment, autoplay: false)
                        },
                        onTrackLabelTap: { trackType in
                            toggleSequentialPlayback(for: trackType)
                        },
                        onAdjustSelectedStart: { delta in
                            adjustSelectedClipStart(by: delta)
                        },
                        onAdjustSelectedEnd: { delta in
                            adjustSelectedClipEnd(by: delta)
                        },
                        onMoveSelected: { delta in
                            moveSelectedClip(by: delta)
                        },
                        onTimelineTimeChanged: { time in
                            scrubTimeline(to: time)
                        }
                    )
                        .frame(height: timelineHeight)
                        .overlay(alignment: .topTrailing) {
                            if match != nil {
                                Button {
                                    isMatchClockSettingsPresented = true
                                } label: {
                                    Label("試合時間", systemImage: "timer")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(Color.black.opacity(0.42)))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .padding(8)
                            }
                        }

                    BottomToolPaletteView(viewModel: viewModel) { tool in
                        handleToolTap(tool)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task {
            await loadPracticalDataIfNeeded()
        }
        .onChange(of: selectedVideoItems) { _, items in
            importSelectedVideos(items)
        }
        .onChange(of: isScrubbingTimeline) { _, isScrubbing in
            // 指を離した瞬間に1回だけ、正確な位置へシークし直す
            guard !isScrubbing else { return }
            pendingScrubSeekTime = nil
            seekPlayerToCurrentTime(selectingSegmentAtCurrentTime: true)
        }
        .sheet(isPresented: $isMatchClockSettingsPresented) {
            if let match {
                let position = matchClockSettingsPosition()
                MatchClockSettingsSheet(
                    initialSettings: matchClockSettings,
                    currentTimelineSecond: position.timelineSecond,
                    currentHalf: position.half,
                    secondHalfTimelineOffset: position.secondHalfTimelineOffset,
                    onSave: { settings in
                        matchClockSettings = settings.normalized()
                        TimelineMatchClockStorage.setSettings(matchClockSettings, for: match.id)
                        loadMatchSegments()
                    }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $isHighlightExportPresented) {
            HighlightExportSheet(
                clips: viewModel.timelineClips,
                videoSegments: viewModel.videoSegments
            )
        }
        .alert("操作できませんでした", isPresented: Binding(
            get: { editorErrorMessage != nil },
            set: { if !$0 { editorErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { editorErrorMessage = nil }
        } message: {
            Text(editorErrorMessage ?? "")
        }
        .onDisappear {
            removePlaybackObserver()
            videoPlayer?.pause()
        }
    }

    private func loadPracticalDataIfNeeded() async {
        loadStoredEventsIfNeeded()
        loadMatchSegments()
        await loadStoredVideosIfNeeded()
        configurePlayerForSelectedVideo(autoplay: false)
    }

    private func loadStoredEventsIfNeeded() {
        guard !didLoadStoredEvents, let match else { return }
        didLoadStoredEvents = true

        do {
            let matchID = match.id
            var descriptor = FetchDescriptor<StatEvent>(
                predicate: #Predicate<StatEvent> { event in
                    event.matchID == matchID
                }
            )
            descriptor.sortBy = [
                SortDescriptor(\.half),
                SortDescriptor(\.seconds)
            ]
            let events = try modelContext.fetch(descriptor)
            viewModel.setTimelineClips(events.compactMap { timelineClip(from: $0, match: match) })
        } catch {
            editorErrorMessage = "イベントを読み込めませんでした。"
        }
    }

    private func loadMatchSegments() {
        guard let match else {
            matchClockSettings = .standard
            viewModel.setMatchSegments([])
            return
        }

        let settings = TimelineMatchClockStorage.settings(for: match.id).normalized()
        matchClockSettings = settings
        let breakDuration: Double = 60
        let firstSegments = makeMatchSegments(
            settings: settings,
            half: 0,
            halfType: .first,
            timelineStart: 0
        )
        let secondStart = Double(settings.actualHalfTimelineDuration(for: 0)) + breakDuration
        let secondSegments = makeMatchSegments(
            settings: settings,
            half: 1,
            halfType: .second,
            timelineStart: secondStart
        )
        let segments = firstSegments + secondSegments
        viewModel.setMatchSegments(segments)
        if let latestMatchTime = segments.map(\.endTime).max(), viewModel.videoSegments.isEmpty {
            viewModel.videoDuration = max(viewModel.videoDuration, latestMatchTime)
        }
    }

    private func makeMatchSegments(
        settings: TimelineMatchClockSettings,
        half: Int,
        halfType: MatchHalfType,
        timelineStart: Double
    ) -> [MatchSegment] {
        let clockDuration = settings.clockDuration(for: half)
        let halfTimelineDuration = settings.actualHalfTimelineDuration(for: half)
        let stops = settings.stoppagesForTimelineScope(half)
        var cursor = 0
        var segments: [MatchSegment] = []

        for stoppage in stops {
            let stopStart = settings.timelineSecond(forClockSecond: stoppage.clockSecond, half: half)
            if stopStart > cursor {
                segments.append(
                    makeMatchSegment(
                        halfType: halfType,
                        timelineStart: timelineStart,
                        localStart: cursor,
                        localEnd: stopStart,
                        clockDuration: clockDuration,
                        isFirstSegmentInHalf: segments.isEmpty
                    )
                )
            }
            cursor = max(cursor, stopStart + max(0, stoppage.durationSeconds))
        }

        if halfTimelineDuration > cursor {
            segments.append(
                makeMatchSegment(
                    halfType: halfType,
                    timelineStart: timelineStart,
                    localStart: cursor,
                    localEnd: halfTimelineDuration,
                    clockDuration: clockDuration,
                    isFirstSegmentInHalf: segments.isEmpty
                )
            )
        }

        if segments.isEmpty {
            segments.append(
                makeMatchSegment(
                    halfType: halfType,
                    timelineStart: timelineStart,
                    localStart: 0,
                    localEnd: max(1, halfTimelineDuration),
                    clockDuration: clockDuration,
                    isFirstSegmentInHalf: true
                )
            )
        }

        return segments
    }

    private func makeMatchSegment(
        halfType: MatchHalfType,
        timelineStart: Double,
        localStart: Int,
        localEnd: Int,
        clockDuration: Int,
        isFirstSegmentInHalf: Bool
    ) -> MatchSegment {
        MatchSegment(
            id: UUID(),
            halfType: halfType,
            startTime: timelineStart + Double(localStart),
            endTime: timelineStart + Double(localEnd),
            displayLabel: isFirstSegmentInHalf
                ? "\(TimelineTimeFormat.duration(Double(clockDuration)))\n(\(halfType.title))"
                : halfType.title
        )
    }

    private func matchClockSettingsPosition() -> (half: Int?, timelineSecond: Double, secondHalfTimelineOffset: Int) {
        let secondHalfStart = viewModel.matchSegments
            .filter { $0.halfType == .second }
            .map(\.startTime)
            .min() ?? 0

        if let first = viewModel.matchSegments.first(where: {
            $0.halfType == .first && $0.startTime <= viewModel.currentVideoTime && viewModel.currentVideoTime <= $0.endTime
        }) {
            return (0, max(0, viewModel.currentVideoTime - first.startTime), Int(secondHalfStart.rounded()))
        }

        if let second = viewModel.matchSegments.first(where: {
            $0.halfType == .second && $0.startTime <= viewModel.currentVideoTime && viewModel.currentVideoTime <= $0.endTime
        }) {
            return (1, max(0, viewModel.currentVideoTime - second.startTime), Int(secondHalfStart.rounded()))
        }

        return (nil, viewModel.currentVideoTime, Int(secondHalfStart.rounded()))
    }

    private func handleToolTap(_ tool: TimelineTrackType) {
        if tool == .deleteTool {
            deleteSelectedTimelineItem()
            return
        }

        guard let match else {
            editorErrorMessage = "試合情報がないため、イベントを保存できません。"
            return
        }

        guard let event = makeStatEvent(for: tool, match: match) else { return }
        modelContext.insert(event)

        do {
            try modelContext.save()
            if let clip = timelineClip(from: event, match: match) {
                viewModel.appendPersistedClip(clip)
            }
        } catch {
            modelContext.delete(event)
            editorErrorMessage = "イベントを保存できませんでした。"
        }
    }

    private func makeStatEvent(for tool: TimelineTrackType, match: Match) -> StatEvent? {
        let start = Int(max(0, viewModel.currentVideoTime).rounded())

        switch tool {
        case .home:
            return StatEvent(
                matchID: match.id,
                teamID: match.homeTeamID,
                category: "possession",
                outcome: "own",
                seconds: 58,
                startSeconds: start
            )
        case .away:
            return StatEvent(
                matchID: match.id,
                teamID: match.awayTeamID,
                category: "possession",
                outcome: "opponent",
                seconds: 58,
                startSeconds: start
            )
        case .bip:
            return StatEvent(
                matchID: match.id,
                category: "possession",
                outcome: "none",
                seconds: 58,
                startSeconds: start
            )
        case .tryEvent:
            return StatEvent(matchID: match.id, category: "try", outcome: "success", seconds: start)
        case .conv:
            return StatEvent(matchID: match.id, category: "conversion", outcome: "success", seconds: start)
        case .pg:
            return StatEvent(matchID: match.id, category: "penalty_goal", outcome: "success", seconds: start)
        case .dg:
            return StatEvent(matchID: match.id, category: "drop_goal", outcome: "success", seconds: start)
        case .lo:
            return StatEvent(matchID: match.id, category: "lineout", outcome: "success", seconds: start)
        case .scr:
            return StatEvent(matchID: match.id, category: "scrum", outcome: "success", seconds: start)
        case .video, .match, .deleteTool:
            return nil
        }
    }

    private func deleteSelectedTimelineItem() {
        if let removedVideo = viewModel.deleteSelectedVideoSegment() {
            if let fileName = removedVideo.fileName {
                if let match {
                    VideoStorage.removeVideoName(fileName, for: match.id)
                }
            }
            configurePlayerForSelectedVideo(autoplay: false)
            return
        }

        guard let selectedClipID = viewModel.selectedClipID else { return }
        if let event = fetchStatEvent(id: selectedClipID) {
            modelContext.delete(event)
            do {
                try modelContext.save()
            } catch {
                editorErrorMessage = "イベントを削除できませんでした。"
                return
            }
        }
        viewModel.deleteSelectedClip()
    }

    private func adjustSelectedClipStart(by delta: Double) {
        guard viewModel.adjustSelectedClipStart(by: delta) else { return }
        saveSelectedClipToEvent()
    }

    private func adjustSelectedClipEnd(by delta: Double) {
        guard viewModel.adjustSelectedClipEnd(by: delta) else { return }
        saveSelectedClipToEvent()
    }

    private func moveSelectedClip(by delta: Double) {
        guard viewModel.moveSelectedClip(by: delta) else { return }
        saveSelectedClipToEvent()
    }

    private func saveSelectedClipToEvent() {
        guard let match,
              let clip = viewModel.clip(id: viewModel.selectedClipID),
              let event = fetchStatEvent(id: clip.id) else { return }

        apply(clip: clip, to: event, match: match)
        do {
            try modelContext.save()
        } catch {
            editorErrorMessage = "イベントの変更を保存できませんでした。"
        }
    }

    private func persistTimelineStateToStorage() {
        guard let match else { return }

        do {
            let matchID = match.id
            let descriptor = FetchDescriptor<StatEvent>(
                predicate: #Predicate<StatEvent> { event in
                    event.matchID == matchID
                }
            )
            let existingEvents = try modelContext.fetch(descriptor)
            let existingByID = Dictionary(uniqueKeysWithValues: existingEvents.map { ($0.id, $0) })
            let timelineClipIDs = Set(viewModel.timelineClips.map(\.id))

            for event in existingEvents {
                if trackType(for: event, match: match) != nil && !timelineClipIDs.contains(event.id) {
                    modelContext.delete(event)
                }
            }

            for clip in viewModel.timelineClips {
                if let existingEvent = existingByID[clip.id] {
                    apply(clip: clip, to: existingEvent, match: match)
                } else if let newEvent = makeStatEvent(from: clip, match: match) {
                    modelContext.insert(newEvent)
                }
            }

            try modelContext.save()

            let videoNames = viewModel.videoSegments.compactMap(\.fileName)
            VideoStorage.setVideoNames(videoNames, for: match.id)
        } catch {
            editorErrorMessage = "編集履歴を保存状態へ反映できませんでした。"
        }
    }

    private func fetchStatEvent(id: UUID) -> StatEvent? {
        var descriptor = FetchDescriptor<StatEvent>(
            predicate: #Predicate<StatEvent> { event in
                event.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func apply(clip: TimelineClip, to event: StatEvent, match: Match) {
        switch clip.trackType {
        case .home:
            event.category = "possession"
            event.teamID = match.homeTeamID
            event.outcome = "own"
            event.startSeconds = Int(max(0, clip.startTime).rounded())
            event.seconds = Int(max(1, clip.endTime - clip.startTime).rounded())
        case .away:
            event.category = "possession"
            event.teamID = match.awayTeamID
            event.outcome = "opponent"
            event.startSeconds = Int(max(0, clip.startTime).rounded())
            event.seconds = Int(max(1, clip.endTime - clip.startTime).rounded())
        case .bip:
            event.category = "possession"
            event.teamID = nil
            event.outcome = "none"
            event.startSeconds = Int(max(0, clip.startTime).rounded())
            event.seconds = Int(max(1, clip.endTime - clip.startTime).rounded())
        default:
            event.category = storageCategory(for: clip.trackType) ?? event.category
            event.outcome = "success"
            event.startSeconds = nil
            event.seconds = Int(max(0, clip.startTime).rounded())
        }
    }

    private func makeStatEvent(from clip: TimelineClip, match: Match) -> StatEvent? {
        switch clip.trackType {
        case .home:
            return StatEvent(
                id: clip.id,
                matchID: match.id,
                teamID: match.homeTeamID,
                category: "possession",
                outcome: "own",
                seconds: Int(max(1, clip.endTime - clip.startTime).rounded()),
                startSeconds: Int(max(0, clip.startTime).rounded())
            )
        case .away:
            return StatEvent(
                id: clip.id,
                matchID: match.id,
                teamID: match.awayTeamID,
                category: "possession",
                outcome: "opponent",
                seconds: Int(max(1, clip.endTime - clip.startTime).rounded()),
                startSeconds: Int(max(0, clip.startTime).rounded())
            )
        case .bip:
            return StatEvent(
                id: clip.id,
                matchID: match.id,
                category: "possession",
                outcome: "none",
                seconds: Int(max(1, clip.endTime - clip.startTime).rounded()),
                startSeconds: Int(max(0, clip.startTime).rounded())
            )
        case .tryEvent, .conv, .pg, .dg, .lo, .scr:
            guard let category = storageCategory(for: clip.trackType) else { return nil }
            return StatEvent(
                id: clip.id,
                matchID: match.id,
                category: category,
                outcome: "success",
                seconds: Int(max(0, clip.startTime).rounded())
            )
        case .video, .match, .deleteTool:
            return nil
        }
    }

    private func timelineClip(from event: StatEvent, match: Match) -> TimelineClip? {
        guard let trackType = trackType(for: event, match: match) else { return nil }
        let start: Double
        let end: Double

        if trackType == .home || trackType == .away || trackType == .bip {
            start = Double(event.startSeconds ?? max(0, event.seconds - 58))
            end = start + Double(max(1, event.seconds))
        } else {
            start = Double(max(0, event.seconds))
            end = start + defaultVisibleLength(for: trackType)
        }

        return TimelineClip(
            id: event.id,
            trackType: trackType,
            startTime: start,
            endTime: min(max(start + 1, end), viewModel.videoDuration),
            title: trackType.title,
            isSelected: event.id == viewModel.selectedClipID
        )
    }

    private func trackType(for event: StatEvent, match: Match) -> TimelineTrackType? {
        switch event.category {
        case "possession":
            if event.outcome == "none" { return .bip }
            if event.teamID == match.awayTeamID || event.outcome == "opponent" { return .away }
            return .home
        case "try": return .tryEvent
        case "conversion": return .conv
        case "penalty_goal": return .pg
        case "drop_goal": return .dg
        case "lineout": return .lo
        case "scrum": return .scr
        default: return nil
        }
    }

    private func storageCategory(for trackType: TimelineTrackType) -> String? {
        switch trackType {
        case .tryEvent: return "try"
        case .conv: return "conversion"
        case .pg: return "penalty_goal"
        case .dg: return "drop_goal"
        case .lo: return "lineout"
        case .scr: return "scrum"
        default: return nil
        }
    }

    private func defaultVisibleLength(for trackType: TimelineTrackType) -> Double {
        switch trackType {
        case .tryEvent, .conv, .pg, .dg, .lo, .scr:
            return 26
        default:
            return 58
        }
    }

    private func importSelectedVideos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isVideoImporting = true
        videoImportProgress = 0

        Task {
            var importedCount = 0
            do {
                for (index, item) in items.enumerated() {
                    guard let movie = try await item.loadTransferable(type: TimelineImportedMovie.self) else {
                        throw TimelineVideoImportError.unavailable
                    }

                    let duration = await videoDurationSeconds(for: movie.fileName)
                    await MainActor.run {
                        let sourceName = "V\(viewModel.videoSegments.count + 1)"
                        let segment = viewModel.addVideoSegment(
                            sourceName: sourceName,
                            duration: duration,
                            fileName: movie.fileName
                        )
                        if let match {
                            VideoStorage.appendVideoNames([movie.fileName], for: match.id)
                        }
                        selectVideoSegment(segment, autoplay: false)
                        importedCount += 1
                        videoImportProgress = Double(index + 1) / Double(max(1, items.count))
                    }
                }

                await MainActor.run {
                    selectedVideoItems = []
                    isVideoImporting = false
                    videoImportProgress = 0
                }
            } catch {
                await MainActor.run {
                    selectedVideoItems = []
                    isVideoImporting = false
                    videoImportProgress = 0
                    editorErrorMessage = importedCount > 0
                        ? "一部の動画だけ読み込みました。読み込めなかった動画があります。"
                        : "動画を読み込めませんでした。別の動画で試してください。"
                }
            }
        }
    }

    private func loadStoredVideosIfNeeded() async {
        guard !didLoadStoredVideos, let match else { return }
        didLoadStoredVideos = true

        let storedNames = VideoStorage.videoNames(for: match.id)
        let availableNames = storedNames.filter { VideoStorage.url(named: $0) != nil }
        guard !availableNames.isEmpty else { return }

        var segments: [VideoSegment] = []
        var cursor: Double = 0

        for (index, fileName) in availableNames.enumerated() {
            let duration = await videoDurationSeconds(for: fileName)
            let end = cursor + max(1, duration)
            segments.append(
                VideoSegment(
                    id: UUID(),
                    sourceName: "V\(index + 1)",
                    startTime: cursor,
                    endTime: end,
                    fileName: fileName
                )
            )
            cursor = end + 12
        }

        viewModel.setVideoSegments(segments)
        configurePlayerForSelectedVideo(autoplay: false)
    }

    private func videoDurationSeconds(for fileName: String) async -> Double {
        guard let url = VideoStorage.url(named: fileName) else { return 1 }
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            return seconds.isFinite && seconds > 0 ? seconds : 1
        } catch {
            return 1
        }
    }

    private func toggleVideoPlayback() {
        if viewModel.isPlaying {
            videoPlayer?.pause()
            viewModel.isPlaying = false
            return
        }

        if let segmentAtTime = playableVideoSegment(at: viewModel.currentVideoTime),
           segmentAtTime.id != viewModel.selectedVideoSegmentID {
            viewModel.selectVideoSegment(segmentAtTime.id)
            configurePlayer(for: segmentAtTime, autoplay: false)
        } else if videoPlayer == nil {
            configurePlayerForSelectedVideo(autoplay: false)
        }

        guard let videoPlayer else {
            editorErrorMessage = "再生できる動画がありません。先に動画を追加してください。"
            return
        }

        videoPlayer.play()
        viewModel.isPlaying = true
    }

    private func selectVideoSegment(_ segment: VideoSegment, autoplay: Bool) {
        viewModel.currentVideoTime = segment.startTime
        viewModel.selectVideoSegment(segment.id)
        configurePlayer(for: segment, autoplay: autoplay)
    }

    private func scrubTimeline(to time: Double) {
        let clampedTime = min(max(0, time), viewModel.videoDuration)
        guard abs(viewModel.currentVideoTime - clampedTime) > 0.03 else { return }

        // 指でスクラブしたら連続再生モードは解除して通常操作に戻す
        clearSequentialPlayback()

        viewModel.currentVideoTime = clampedTime
        videoPlayer?.pause()
        viewModel.isPlaying = false

        if isScrubbingTimeline {
            // スクラブ中: 粗い精度のシークを直列に間引いて発行する。
            // 毎フレーム誤差ゼロシークを発行すると詰まってカクつくため。
            requestScrubSeek(to: clampedTime)
        } else {
            // タップ等の単発移動は即・正確にシーク
            seekPlayerToCurrentTime(selectingSegmentAtCurrentTime: true)
        }
    }

    // 「最後に要求された時刻」だけを覚えておき、前のシークが終わってから次を出す
    private func requestScrubSeek(to time: Double) {
        pendingScrubSeekTime = time
        performPendingScrubSeek()
    }

    private func performPendingScrubSeek() {
        guard !isScrubSeekInFlight, let target = pendingScrubSeekTime else { return }
        guard let segment = playableVideoSegment(at: target) else { return }

        if activeVideoSegmentID != segment.id || videoPlayer == nil {
            pendingScrubSeekTime = nil
            viewModel.selectVideoSegment(segment.id)
            configurePlayer(for: segment, autoplay: false)
            return
        }

        guard let player = videoPlayer else { return }
        pendingScrubSeekTime = nil
        isScrubSeekInFlight = true
        let localTime = min(max(0, target - segment.startTime), max(0, segment.endTime - segment.startTime))
        let tolerance = CMTime(seconds: 0.3, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: localTime, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { _ in
            Task { @MainActor in
                isScrubSeekInFlight = false
                performPendingScrubSeek()
            }
        }
    }

    // ===== トラック連続再生 =====
    // 左のラベル(HOME など)をタップすると、その行のクリップ区間だけを
    // 時系列順に動画で連続再生する。区間の合間は自動でスキップ。

    private func toggleSequentialPlayback(for trackType: TimelineTrackType) {
        if selectedPlaybackTrack == trackType {
            clearSequentialPlayback()
            videoPlayer?.pause()
            viewModel.isPlaying = false
            return
        }

        let queue = sequentialPlaybackQueue(for: trackType)
        guard !queue.isEmpty else {
            editorErrorMessage = "\(trackType.title) のクリップがまだありません。"
            return
        }
        // 動画が重なっている最初の区間から始める
        guard let firstIndex = queue.firstIndex(where: { playableVideoSegment(at: $0.start) != nil }) else {
            editorErrorMessage = "\(trackType.title) のクリップに重なる動画がありません。"
            return
        }

        selectedPlaybackTrack = trackType
        playbackQueue = queue
        playbackQueueIndex = firstIndex
        jumpPlayback(to: queue[firstIndex].start, keepPlaying: true)
    }

    private func clearSequentialPlayback() {
        selectedPlaybackTrack = nil
        playbackQueue = []
        playbackQueueIndex = 0
    }

    // その行のクリップを時系列順に並べ、重なる・つながる区間は1つにまとめる
    private func sequentialPlaybackQueue(for trackType: TimelineTrackType) -> [(start: Double, end: Double)] {
        let clips = viewModel.timelineClips
            .filter { $0.trackType == trackType && $0.endTime > $0.startTime }
            .sorted { $0.startTime < $1.startTime }

        var merged: [(start: Double, end: Double)] = []
        for clip in clips {
            if let last = merged.last, clip.startTime <= last.end + 0.5 {
                merged[merged.count - 1].end = max(last.end, clip.endTime)
            } else {
                merged.append((clip.startTime, clip.endTime))
            }
        }
        return merged
    }

    // 再生を続けたまま、タイムライン上の指定時刻へ動画を飛ばす
    private func jumpPlayback(to time: Double, keepPlaying: Bool) {
        let clampedTime = min(max(0, time), viewModel.videoDuration)
        viewModel.currentVideoTime = clampedTime

        guard let segment = playableVideoSegment(at: clampedTime) else { return }

        if activeVideoSegmentID != segment.id || videoPlayer == nil {
            viewModel.selectVideoSegment(segment.id)
            configurePlayer(for: segment, autoplay: keepPlaying)
        } else {
            let localTime = min(max(0, clampedTime - segment.startTime), max(0, segment.endTime - segment.startTime))
            videoPlayer?.seek(
                to: CMTime(seconds: localTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            if keepPlaying {
                videoPlayer?.play()
                viewModel.isPlaying = true
            }
        }
    }

    // 再生位置が今の区間の終わりまで来たら、次の区間へ自動で飛ぶ。
    // 動画の時間監視(0.2秒ごと)から呼ばれる。
    private func checkSequentialPlaybackProgress() {
        guard selectedPlaybackTrack != nil,
              viewModel.isPlaying,
              playbackQueueIndex < playbackQueue.count else {
            return
        }
        let current = playbackQueue[playbackQueueIndex]
        guard viewModel.currentVideoTime >= current.end - 0.1 else { return }

        var nextIndex = playbackQueueIndex + 1
        // 動画が重なっていない区間は飛ばす
        while nextIndex < playbackQueue.count,
              playableVideoSegment(at: playbackQueue[nextIndex].start) == nil {
            nextIndex += 1
        }

        guard nextIndex < playbackQueue.count else {
            // 最後の区間まで見終わったら停止して選択も解除
            videoPlayer?.pause()
            viewModel.isPlaying = false
            clearSequentialPlayback()
            return
        }

        playbackQueueIndex = nextIndex
        jumpPlayback(to: playbackQueue[nextIndex].start, keepPlaying: true)
    }

    private func seekPlayerToCurrentTime(selectingSegmentAtCurrentTime: Bool) {
        let segment: VideoSegment?
        if selectingSegmentAtCurrentTime {
            segment = playableVideoSegment(at: viewModel.currentVideoTime)
                ?? viewModel.videoSegment(id: viewModel.selectedVideoSegmentID)
        } else {
            segment = viewModel.videoSegment(id: viewModel.selectedVideoSegmentID)
        }

        guard let segment else { return }

        if activeVideoSegmentID != segment.id || videoPlayer == nil {
            viewModel.selectVideoSegment(segment.id)
            configurePlayer(for: segment, autoplay: false)
            return
        }

        let localTime = min(max(0, viewModel.currentVideoTime - segment.startTime), max(0, segment.endTime - segment.startTime))
        videoPlayer?.seek(
            to: CMTime(seconds: localTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func playableVideoSegment(at time: Double) -> VideoSegment? {
        viewModel.videoSegments.first { segment in
            segment.fileName != nil && segment.startTime <= time && time <= segment.endTime
        }
    }

    private func configurePlayerForSelectedVideo(autoplay: Bool) {
        guard let segment = viewModel.videoSegment(id: viewModel.selectedVideoSegmentID)
                ?? viewModel.videoSegments.first(where: { $0.fileName != nil }) else {
            removePlaybackObserver()
            videoPlayer?.pause()
            videoPlayer = nil
            activeVideoSegmentID = nil
            viewModel.isPlaying = false
            return
        }
        viewModel.selectVideoSegment(segment.id)
        configurePlayer(for: segment, autoplay: autoplay)
    }

    private func configurePlayer(for segment: VideoSegment, autoplay: Bool) {
        guard let fileName = segment.fileName,
              let url = VideoStorage.url(named: fileName) else {
            removePlaybackObserver()
            videoPlayer?.pause()
            videoPlayer = nil
            activeVideoSegmentID = nil
            viewModel.isPlaying = false
            editorErrorMessage = "この動画ファイルを開けませんでした。"
            return
        }

        let player: AVPlayer
        if activeVideoSegmentID == segment.id, let existingPlayer = videoPlayer {
            player = existingPlayer
        } else {
            removePlaybackObserver()
            player = AVPlayer(url: url)
            videoPlayer = player
            activeVideoSegmentID = segment.id
            addPlaybackObserver(to: player, segment: segment)
            addVideoEndObserver(to: player)
        }

        let localTime = min(max(0, viewModel.currentVideoTime - segment.startTime), max(0, segment.endTime - segment.startTime))
        player.seek(to: CMTime(seconds: localTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)

        if autoplay {
            player.play()
            viewModel.isPlaying = true
        } else {
            player.pause()
            viewModel.isPlaying = false
        }
    }

    private func addPlaybackObserver(to player: AVPlayer, segment: VideoSegment) {
        playbackTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in
                viewModel.currentVideoTime = min(viewModel.videoDuration, segment.startTime + seconds)
                checkSequentialPlaybackProgress()
            }
        }
    }

    private func removePlaybackObserver() {
        if let playbackTimeObserver, let videoPlayer {
            videoPlayer.removeTimeObserver(playbackTimeObserver)
        }
        playbackTimeObserver = nil
        removeVideoEndObserver()
    }

    // ===== 動画ファイルの終端処理 =====
    // 1本目の動画が最後まで再生されたら、タイムライン上の次の動画へ自動で続ける。
    // 1本目の終わりと2本目の頭の間が空いていても(撮影のラグ等)、待たずに飛ばす。

    private func addVideoEndObserver(to player: AVPlayer) {
        removeVideoEndObserver()
        guard let item = player.currentItem else { return }
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handleVideoDidPlayToEnd()
            }
        }
    }

    private func removeVideoEndObserver() {
        if let videoEndObserver {
            NotificationCenter.default.removeObserver(videoEndObserver)
        }
        videoEndObserver = nil
    }

    private func handleVideoDidPlayToEnd() {
        guard viewModel.isPlaying else { return }

        // ファイルが付いている動画セグメントを時系列に並べ、今の次を探す
        let playableSegments = viewModel.videoSegments
            .filter { $0.fileName != nil }
            .sorted { $0.startTime < $1.startTime }

        guard let activeID = activeVideoSegmentID,
              let activeIndex = playableSegments.firstIndex(where: { $0.id == activeID }),
              activeIndex + 1 < playableSegments.count else {
            // 次の動画がなければここで停止
            videoPlayer?.pause()
            viewModel.isPlaying = false
            return
        }

        let next = playableSegments[activeIndex + 1]
        jumpPlayback(to: next.startTime, keepPlaying: true)
    }
}

struct TimelineHeaderView: View {
    var onBack: () -> Void
    var onExport: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.white.opacity(0.09)))
                    .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
            }

            Spacer()

            Text("タイムライン編集")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.white.opacity(0.09)))
                    .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
            }
        }
        .frame(height: 54)
    }
}

struct VideoPreviewCard: View {
    var videoSegments: [VideoSegment]
    var player: AVPlayer?
    var selectedVideoSegmentID: UUID?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if let player {
                    TimelineVideoPlayerView(player: player)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.58))
                        Text("動画を追加してください")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }

                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(videoSegments) { segment in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(segment.id == selectedVideoSegmentID ? Color.white.opacity(0.80) : Color.white.opacity(0.24))
                                .frame(
                                    width: max(34, proxy.size.width * CGFloat((segment.endTime - segment.startTime) / 960) * 0.22),
                                    height: 4
                                )
                        }
                        Spacer()
                    }
                    .padding(14)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.30), radius: 18, x: 0, y: 10)
        }
    }
}

struct PlaybackControlBar: View {
    var currentVideoTime: Double
    var videoDuration: Double
    var isPlaying: Bool
    var canUndo: Bool
    var canRedo: Bool
    var onPlayPause: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void

    var body: some View {
        HStack {
            Text("\(TimelineTimeFormat.videoClock(currentVideoTime)) / \(TimelineTimeFormat.duration(videoDuration))")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
            }

            HStack(spacing: 12) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .disabled(!canUndo)
                .opacity(canUndo ? 1 : 0.34)

                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .disabled(!canRedo)
                .opacity(canRedo ? 1 : 0.34)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.01, green: 0.06, blue: 0.12).opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - タイムライン描画(Canvas 1枚 + 物理スクロール)
//
// 仕組み(重くしないための設計):
// - 横スクロールは「中身が空の UIScrollView」を物理エンジンとしてだけ使う。
//   慣性・バウンドはネイティブのまま、位置(offset)だけを受け取る。
// - 見た目は、見えている範囲だけを Canvas に毎回描く。クリップを1つずつ
//   ビューにしない → クリップが何百個あっても描画コストがほぼ一定。
// - 再生ヘッドは画面中央に固定し、スクロール位置 = 再生時刻。
// - ピンチで拡大縮小(再生ヘッド中心)。選択クリップは掴んで移動・両端で伸縮。

private enum ClipDragMode {
    case move
    case start
    case end
}

private struct ClipDragPreview: Equatable {
    var mode: ClipDragMode?
    var delta: Double

    static let inactive = ClipDragPreview(mode: nil, delta: 0)
}

struct TimelineTracksView: View {
    @ObservedObject var viewModel: TimelineEditorViewModel
    @Binding var isScrubbingTimeline: Bool
    var selectedPlaybackTrack: TimelineTrackType?
    var onSelectVideoSegment: (VideoSegment) -> Void
    var onTrackLabelTap: (TimelineTrackType) -> Void
    var onAdjustSelectedStart: (Double) -> Void
    var onAdjustSelectedEnd: (Double) -> Void
    var onMoveSelected: (Double) -> Void
    var onTimelineTimeChanged: (Double) -> Void

    private let labelWidth: CGFloat = 110
    private let rulerHeight: CGFloat = 42
    private let rowHeight: CGFloat = 48

    // 横スクロール位置と拡大率は、このビューの中で完結させる
    @State private var scrollOffset: CGFloat = 0
    @State private var pixelsPerSecond: CGFloat = 1.55
    @State private var pinchBasePPS: CGFloat?
    @State private var pinchFocusTime: Double = 0
    @State private var dragPreview: ClipDragPreview = .inactive

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = max(1, proxy.size.width - labelWidth)
            let playheadX = proxy.size.width / 2
            let leadingInset = max(0, playheadX - labelWidth)
            let contentWidth = CGFloat(viewModel.videoDuration) * pixelsPerSecond + viewportWidth
            let rowsHeight = CGFloat(viewModel.visibleTracks.count) * rowHeight

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.01, green: 0.05, blue: 0.10).opacity(0.90))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.11), lineWidth: 1)
                    )

                VStack(spacing: 0) {
                    // 目盛り(上部に固定・タップでその時刻へ移動)
                    HStack(spacing: 0) {
                        Color.clear.frame(width: labelWidth, height: rulerHeight)

                        ZStack(alignment: .topLeading) {
                            TimelineScrollPhysicsView(
                                offset: $scrollOffset,
                                isTracking: $isScrubbingTimeline,
                                contentWidth: contentWidth,
                                onTap: { point in
                                    jumpToTapped(contentX: point.x, leadingInset: leadingInset)
                                }
                            )

                            TimelineRulerCanvas(
                                duration: viewModel.videoDuration,
                                pixelsPerSecond: pixelsPerSecond,
                                offset: scrollOffset,
                                leadingInset: leadingInset
                            )
                            .allowsHitTesting(false)
                        }
                        .frame(width: viewportWidth, height: rulerHeight)
                        .clipped()
                    }

                    // トラック(縦にスクロール可)
                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                ForEach(viewModel.visibleTracks) { trackType in
                                    TimelineTrackLabelView(
                                        trackType: trackType,
                                        isSelected: selectedPlaybackTrack == trackType,
                                        onTap: trackType.supportsSequentialPlayback
                                            ? { onTrackLabelTap(trackType) }
                                            : nil
                                    )
                                    .frame(width: labelWidth, height: rowHeight)
                                    .overlay(alignment: .bottom) {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.07))
                                            .frame(height: 1)
                                    }
                                }
                            }

                            ZStack(alignment: .topLeading) {
                                TimelineScrollPhysicsView(
                                    offset: $scrollOffset,
                                    isTracking: $isScrubbingTimeline,
                                    contentWidth: contentWidth,
                                    onTap: { point in
                                        handleRowsTap(contentPoint: point, leadingInset: leadingInset)
                                    },
                                    onPinchBegan: {
                                        pinchBasePPS = pixelsPerSecond
                                        pinchFocusTime = viewModel.currentVideoTime
                                    },
                                    onPinchChanged: { scale in
                                        guard let base = pinchBasePPS else { return }
                                        pixelsPerSecond = min(max(base * scale, 0.5), 10)
                                        scrollOffset = CGFloat(pinchFocusTime) * pixelsPerSecond
                                    },
                                    onPinchEnded: {
                                        pinchBasePPS = nil
                                    }
                                )

                                TimelineRowsCanvas(
                                    tracks: viewModel.visibleTracks,
                                    rowHeight: rowHeight,
                                    duration: viewModel.videoDuration,
                                    pixelsPerSecond: pixelsPerSecond,
                                    offset: scrollOffset,
                                    leadingInset: leadingInset,
                                    clips: viewModel.timelineClips,
                                    matchSegments: viewModel.matchSegments,
                                    videoSegments: viewModel.videoSegments,
                                    selectedClipID: viewModel.selectedClipID,
                                    selectedVideoSegmentID: viewModel.selectedVideoSegmentID,
                                    playbackTrack: selectedPlaybackTrack,
                                    dragPreview: dragPreview
                                )
                                .allowsHitTesting(false)

                                selectedClipOverlay(leadingInset: leadingInset, viewportWidth: viewportWidth)
                            }
                            .frame(width: viewportWidth, height: rowsHeight)
                            .clipped()
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
                    .position(x: labelWidth, y: proxy.size.height / 2)
                    .allowsHitTesting(false)

                if viewModel.videoSegments.isEmpty {
                    Text("動画を追加すると、ここに実際のクリップが表示されます")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.36))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: viewportWidth - 24)
                        .position(x: labelWidth + viewportWidth / 2, y: rulerHeight + rowHeight / 2)
                        .allowsHitTesting(false)
                }

                // 再生ヘッド(中央固定)
                VStack(spacing: 0) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: Color.white.opacity(0.60), radius: 8)
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                }
                .frame(height: proxy.size.height - 12)
                .position(x: playheadX, y: proxy.size.height / 2 + 6)
                .allowsHitTesting(false)
            }
            .onAppear {
                scrollOffset = CGFloat(viewModel.currentVideoTime) * pixelsPerSecond
            }
            .onChange(of: viewModel.currentVideoTime) { _, newTime in
                guard !isScrubbingTimeline, pinchBasePPS == nil else { return }
                scrollOffset = CGFloat(newTime) * pixelsPerSecond
            }
            .onChange(of: scrollOffset) { _, newOffset in
                guard isScrubbingTimeline else { return }
                onTimelineTimeChanged(Double(newOffset / max(1, pixelsPerSecond)))
            }
        }
    }

    // MARK: 選択クリップの操作レイヤー(移動・伸縮)

    @ViewBuilder
    private func selectedClipOverlay(leadingInset: CGFloat, viewportWidth: CGFloat) -> some View {
        if let clip = viewModel.clip(id: viewModel.selectedClipID),
           let rowIndex = viewModel.visibleTracks.firstIndex(of: clip.trackType) {
            let times = previewedTimes(for: clip)
            let x = leadingInset + CGFloat(times.start) * pixelsPerSecond - scrollOffset
            let width = max(28, CGFloat(times.end - times.start) * pixelsPerSecond)
            let y = CGFloat(rowIndex) * rowHeight

            if x + width > -60, x < viewportWidth + 60 {
                // 本体: 掴んで左右へ移動
                Color.clear
                    .frame(width: width, height: rowHeight - 14)
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .position(x: x + width / 2, y: y + rowHeight / 2)
                    .gesture(dragGesture(mode: .move))

                // 両端: 伸縮ハンドル
                TimelineClipResizeHandle()
                    .frame(width: 34, height: rowHeight)
                    .contentShape(Rectangle())
                    .position(x: x, y: y + rowHeight / 2)
                    .gesture(dragGesture(mode: .start))

                TimelineClipResizeHandle()
                    .frame(width: 34, height: rowHeight)
                    .contentShape(Rectangle())
                    .position(x: x + width, y: y + rowHeight / 2)
                    .gesture(dragGesture(mode: .end))
            }
        }
    }

    private func dragGesture(mode: ClipDragMode) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                dragPreview = ClipDragPreview(
                    mode: mode,
                    delta: Double(value.translation.width / max(1, pixelsPerSecond))
                )
            }
            .onEnded { value in
                let delta = Double(value.translation.width / max(1, pixelsPerSecond))
                dragPreview = .inactive
                switch mode {
                case .move: onMoveSelected(delta)
                case .start: onAdjustSelectedStart(delta)
                case .end: onAdjustSelectedEnd(delta)
                }
            }
    }

    private func previewedTimes(for clip: TimelineClip) -> (start: Double, end: Double) {
        var start = clip.startTime
        var end = clip.endTime

        switch dragPreview.mode {
        case .move:
            let length = end - start
            start = min(max(0, start + dragPreview.delta), max(0, viewModel.videoDuration - length))
            end = start + length
        case .start:
            start = min(max(0, start + dragPreview.delta), end - 1)
        case .end:
            end = max(min(viewModel.videoDuration, end + dragPreview.delta), start + 1)
        case nil:
            break
        }

        return (start, end)
    }

    // MARK: タップの解釈

    private func jumpToTapped(contentX: CGFloat, leadingInset: CGFloat) {
        let time = min(max(0, Double((contentX - leadingInset) / max(1, pixelsPerSecond))), viewModel.videoDuration)
        scrollOffset = CGFloat(time) * pixelsPerSecond
        onTimelineTimeChanged(time)
    }

    private func handleRowsTap(contentPoint: CGPoint, leadingInset: CGFloat) {
        let rowIndex = Int(contentPoint.y / rowHeight)
        guard rowIndex >= 0, rowIndex < viewModel.visibleTracks.count else { return }
        let trackType = viewModel.visibleTracks[rowIndex]
        let time = Double((contentPoint.x - leadingInset) / max(1, pixelsPerSecond))
        // 細いクリップも拾えるよう、±10pt ぶんの遊びを持たせる
        let slop = Double(10 / max(1, pixelsPerSecond))

        switch trackType {
        case .video:
            if let segment = viewModel.videoSegments.first(where: {
                $0.startTime - slop <= time && time <= $0.endTime + slop
            }) {
                onSelectVideoSegment(segment)
            }
        case .match, .deleteTool:
            viewModel.selectClip(nil)
        default:
            let candidates = viewModel.timelineClips.filter {
                $0.trackType == trackType && $0.startTime - slop <= time && time <= $0.endTime + slop
            }
            if let hit = candidates.min(by: {
                abs((($0.startTime + $0.endTime) / 2) - time) < abs((($1.startTime + $1.endTime) / 2) - time)
            }) {
                viewModel.selectClip(hit.id)
            } else {
                viewModel.selectClip(nil)
            }
        }
    }
}

// MARK: - 物理エンジンとしての空スクロールビュー

private struct TimelineScrollPhysicsView: UIViewRepresentable {
    @Binding var offset: CGFloat
    @Binding var isTracking: Bool
    var contentWidth: CGFloat
    var onTap: ((CGPoint) -> Void)? = nil
    var onPinchBegan: (() -> Void)? = nil
    var onPinchChanged: ((CGFloat) -> Void)? = nil
    var onPinchEnded: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false

        if onTap != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tap.cancelsTouchesInView = false
            scrollView.addGestureRecognizer(tap)
        }
        if onPinchChanged != nil {
            let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
            scrollView.addGestureRecognizer(pinch)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        // setContentOffset は delegate を同期的に呼ぶ。SwiftUI の画面更新中に
        // 状態を書き戻さないよう、フラグを立てて delegate 側で遅延させる。
        context.coordinator.isPerformingViewUpdate = true
        defer { context.coordinator.isPerformingViewUpdate = false }

        if abs(scrollView.contentSize.width - contentWidth) > 0.5 {
            scrollView.contentSize = CGSize(width: contentWidth, height: 1)
        }

        let maxOffset = max(0, contentWidth - scrollView.bounds.width)
        let clampedOffset = min(max(0, offset), maxOffset)
        if abs(scrollView.contentOffset.x - clampedOffset) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: clampedOffset, y: 0), animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: TimelineScrollPhysicsView
        var isPerformingViewUpdate = false

        init(_ parent: TimelineScrollPhysicsView) {
            self.parent = parent
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            setIsTracking(true)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let x = scrollView.contentOffset.x
            if isPerformingViewUpdate {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.offset = x
                }
            } else {
                parent.offset = x
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                setIsTracking(false)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            setIsTracking(false)
        }

        private func setIsTracking(_ value: Bool) {
            if isPerformingViewUpdate {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isTracking = value
                }
            } else {
                parent.isTracking = value
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            parent.onTap?(recognizer.location(in: scrollView))
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            switch recognizer.state {
            case .began:
                // ピンチ中は横スクロールを止めて、拡大縮小に専念させる
                scrollView.isScrollEnabled = false
                parent.onPinchBegan?()
            case .changed:
                parent.onPinchChanged?(recognizer.scale)
            default:
                scrollView.isScrollEnabled = true
                parent.onPinchEnded?()
            }
        }
    }
}

// MARK: - 目盛りの描画

private struct TimelineRulerCanvas: View {
    var duration: Double
    var pixelsPerSecond: CGFloat
    var offset: CGFloat
    var leadingInset: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.white.opacity(0.035))
            )

            let pps = max(0.1, pixelsPerSecond)
            func xFor(_ t: Double) -> CGFloat { leadingInset + CGFloat(t) * pps - offset }

            let visibleStart = max(0, Double((offset - leadingInset) / pps))
            let visibleEnd = min(duration, Double((offset - leadingInset + size.width) / pps) + 1)
            guard visibleEnd > visibleStart else { return }

            // ラベルを付ける間隔(分)は、詰まらない最小の間隔をズームから選ぶ
            let stepCandidates = [1, 2, 5, 10, 15, 30]
            let labelStep = stepCandidates.first(where: { CGFloat($0) * 60 * pps >= 64 }) ?? 30

            let firstMinute = max(0, Int(visibleStart / 60))
            let lastMinute = Int(visibleEnd / 60) + 1
            if lastMinute >= firstMinute {
                for minute in firstMinute...lastMinute {
                    let t = Double(minute * 60)
                    if t > duration + 0.5 { break }
                    let x = xFor(t)
                    let isLabeled = minute % labelStep == 0

                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height))
                    tick.addLine(to: CGPoint(x: x, y: size.height - (isLabeled ? 16 : 9)))
                    context.stroke(tick, with: .color(Color.white.opacity(isLabeled ? 0.42 : 0.20)), lineWidth: 1)

                    if isLabeled {
                        context.draw(
                            Text(TimelineTimeFormat.rulerMinute(minute))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.72)),
                            at: CGPoint(x: x, y: 12)
                        )
                    }
                }
            }

            // 拡大しているときは10秒の小目盛りも足す
            if pps >= 3 {
                let firstTick = max(0, Int(visibleStart / 10))
                let lastTick = Int(visibleEnd / 10) + 1
                if lastTick >= firstTick {
                    for tickIndex in firstTick...lastTick where tickIndex % 6 != 0 {
                        let t = Double(tickIndex * 10)
                        if t > duration { break }
                        var tick = Path()
                        tick.move(to: CGPoint(x: xFor(t), y: size.height))
                        tick.addLine(to: CGPoint(x: xFor(t), y: size.height - 5))
                        context.stroke(tick, with: .color(Color.white.opacity(0.14)), lineWidth: 1)
                    }
                }
            }
        }
    }
}

// MARK: - トラックの描画(全クリップを1枚に描く)

private struct TimelineRowsCanvas: View {
    var tracks: [TimelineTrackType]
    var rowHeight: CGFloat
    var duration: Double
    var pixelsPerSecond: CGFloat
    var offset: CGFloat
    var leadingInset: CGFloat
    var clips: [TimelineClip]
    var matchSegments: [MatchSegment]
    var videoSegments: [VideoSegment]
    var selectedClipID: UUID?
    var selectedVideoSegmentID: UUID?
    var playbackTrack: TimelineTrackType?
    var dragPreview: ClipDragPreview

    var body: some View {
        Canvas { context, size in
            let pps = max(0.1, pixelsPerSecond)
            func xFor(_ t: Double) -> CGFloat { leadingInset + CGFloat(t) * pps - offset }
            let visibleStart = Double((offset - leadingInset) / pps)
            let visibleEnd = Double((offset - leadingInset + size.width) / pps)

            // 行の背景と区切り線
            for (index, track) in tracks.enumerated() {
                let y = CGFloat(index) * rowHeight
                let rowRect = CGRect(x: 0, y: y, width: size.width, height: rowHeight)

                if track == .video || track == .match {
                    context.fill(Path(rowRect), with: .color(Color.white.opacity(0.03)))
                }
                if track == playbackTrack {
                    context.fill(Path(rowRect), with: .color(track.color.opacity(0.10)))
                }

                var separator = Path()
                separator.move(to: CGPoint(x: 0, y: y + rowHeight))
                separator.addLine(to: CGPoint(x: size.width, y: y + rowHeight))
                context.stroke(separator, with: .color(Color.white.opacity(0.07)), lineWidth: 1)
            }

            // 5分ごとの縦グリッド
            let gridStep: Double = 300
            var gridTime = max(0, (visibleStart / gridStep).rounded(.down) * gridStep)
            while gridTime <= min(duration, visibleEnd) {
                var line = Path()
                line.move(to: CGPoint(x: xFor(gridTime), y: 0))
                line.addLine(to: CGPoint(x: xFor(gridTime), y: size.height))
                context.stroke(line, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
                gridTime += gridStep
            }

            // 各行の中身
            for (index, track) in tracks.enumerated() {
                let y = CGFloat(index) * rowHeight
                switch track {
                case .video:
                    drawVideoRow(context: context, y: y, xFor: xFor, pps: pps, visibleStart: visibleStart, visibleEnd: visibleEnd)
                case .match:
                    drawMatchRow(context: context, y: y, xFor: xFor, pps: pps, visibleStart: visibleStart, visibleEnd: visibleEnd)
                case .deleteTool:
                    break
                default:
                    drawEventRow(context: context, track: track, y: y, xFor: xFor, pps: pps, visibleStart: visibleStart, visibleEnd: visibleEnd)
                }
            }
        }
    }

    private func drawEventRow(
        context: GraphicsContext,
        track: TimelineTrackType,
        y: CGFloat,
        xFor: (Double) -> CGFloat,
        pps: CGFloat,
        visibleStart: Double,
        visibleEnd: Double
    ) {
        for clip in clips where clip.trackType == track {
            var start = clip.startTime
            var end = clip.endTime

            // ドラッグ中の選択クリップは、指についてくる位置で描く
            if clip.id == selectedClipID, dragPreview.mode != nil {
                switch dragPreview.mode {
                case .move:
                    let length = end - start
                    start = min(max(0, start + dragPreview.delta), max(0, duration - length))
                    end = start + length
                case .start:
                    start = min(max(0, start + dragPreview.delta), end - 1)
                case .end:
                    end = max(min(duration, end + dragPreview.delta), start + 1)
                case nil:
                    break
                }
            }

            guard end > visibleStart - 2, start < visibleEnd + 2 else { continue }

            let startX = xFor(start)
            let width = max(28, CGFloat(end - start) * pps)
            let rect = CGRect(x: startX, y: y + 7, width: width, height: rowHeight - 14)
            let path = Path(roundedRect: rect, cornerRadius: 6)
            let isSelected = clip.id == selectedClipID

            if isSelected {
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: -2.5, dy: -2.5), cornerRadius: 8),
                    with: .color(clip.color.opacity(0.45)),
                    lineWidth: 5
                )
            }
            context.fill(path, with: .color(clip.color.opacity(0.92)))
            context.stroke(
                path,
                with: .color(isSelected ? .white : Color.white.opacity(0.25)),
                lineWidth: isSelected ? 2 : 1
            )

            if width >= 42 {
                var clipped = context
                clipped.clip(to: path)
                clipped.draw(
                    Text(clip.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white),
                    at: CGPoint(x: rect.minX + 8, y: rect.midY),
                    anchor: .leading
                )
            }
        }
    }

    private func drawVideoRow(
        context: GraphicsContext,
        y: CGFloat,
        xFor: (Double) -> CGFloat,
        pps: CGFloat,
        visibleStart: Double,
        visibleEnd: Double
    ) {
        for segment in videoSegments {
            guard segment.endTime > visibleStart - 2, segment.startTime < visibleEnd + 2 else { continue }

            let startX = xFor(segment.startTime)
            let width = max(34, CGFloat(segment.endTime - segment.startTime) * pps)
            let rect = CGRect(x: startX, y: y + 8, width: width, height: rowHeight - 16)
            let path = Path(roundedRect: rect, cornerRadius: 6)
            let isSelected = segment.id == selectedVideoSegmentID

            context.fill(path, with: .color(TimelineTrackType.video.color.opacity(0.85)))
            context.stroke(
                path,
                with: .color(isSelected ? .white : Color.white.opacity(0.32)),
                lineWidth: isSelected ? 2 : 1
            )

            var clipped = context
            clipped.clip(to: path)
            clipped.draw(
                Text("\(Image(systemName: "film.fill")) \(segment.sourceName)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white),
                at: CGPoint(x: rect.minX + 8, y: rect.midY),
                anchor: .leading
            )
        }
    }

    private func drawMatchRow(
        context: GraphicsContext,
        y: CGFloat,
        xFor: (Double) -> CGFloat,
        pps: CGFloat,
        visibleStart: Double,
        visibleEnd: Double
    ) {
        let sorted = matchSegments.sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
            return lhs.endTime < rhs.endTime
        }

        // 区間の切れ目(停止・中断)は破線で示す
        if sorted.count >= 2 {
            for index in 0..<(sorted.count - 1) {
                let current = sorted[index]
                let next = sorted[index + 1]
                guard next.startTime > current.endTime,
                      next.startTime > visibleStart - 2,
                      current.endTime < visibleEnd + 2 else { continue }

                let rect = CGRect(
                    x: xFor(current.endTime),
                    y: y + 12,
                    width: max(20, CGFloat(next.startTime - current.endTime) * pps),
                    height: rowHeight - 24
                )
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 5),
                    with: .color(Color.white.opacity(0.26)),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
                context.draw(
                    Text(current.halfType == next.halfType ? "停止" : "中断")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.58)),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            }
        }

        let matchColor = TimelineTrackType.match.color
        for segment in sorted {
            guard segment.endTime > visibleStart - 2, segment.startTime < visibleEnd + 2 else { continue }

            let startX = xFor(segment.startTime)
            let width = max(34, CGFloat(segment.endTime - segment.startTime) * pps)
            let rect = CGRect(x: startX, y: y + 9, width: width, height: rowHeight - 18)
            let path = Path(roundedRect: rect, cornerRadius: 6)

            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [matchColor.opacity(0.48), matchColor.opacity(0.18)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )
            context.stroke(path, with: .color(matchColor.opacity(0.95)), lineWidth: 1)

            var clipped = context
            clipped.clip(to: path)
            clipped.draw(
                Text(segment.displayLabel.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94)),
                at: CGPoint(x: rect.minX + 8, y: rect.midY),
                anchor: .leading
            )
        }
    }
}

private struct TimelineTrackLabelView: View {
    var trackType: TimelineTrackType
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        let label = HStack(spacing: 8) {
            Image(systemName: trackType.systemImage)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(trackType.color)
                .frame(width: 28)

            Text(trackType.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(isSelected ? 0.95 : 0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(isSelected ? trackType.color.opacity(0.24) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(trackType.color)
                    .frame(width: 3)
            }
        }

        if let onTap {
            Button(action: onTap) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }
}

private struct TimelineClipResizeHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.90))
            .frame(width: 14, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.black.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: Color.white.opacity(0.35), radius: 4)
    }
}

struct BottomToolPaletteView: View {
    @ObservedObject var viewModel: TimelineEditorViewModel
    var onToolTap: (TimelineTrackType) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(TimelineTrackType.toolPalette) { tool in
                    Button {
                        onToolTap(tool)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 26, weight: .bold))
                                .frame(height: 30)

                            Text(tool.title)
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.64)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(tool.color.gradient)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(
                                    viewModel.selectedTool == tool ? Color.white : Color.white.opacity(0.16),
                                    lineWidth: viewModel.selectedTool == tool ? 3 : 1
                                )
                        )
                        .shadow(
                            color: viewModel.selectedTool == tool ? tool.color.opacity(0.62) : Color.black.opacity(0.24),
                            radius: viewModel.selectedTool == tool ? 12 : 5,
                            x: 0,
                            y: 5
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(height: 98)
    }
}

private enum TimelineTimeFormat {
    static func videoClock(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let wholeSeconds = Int(clamped) % 60
        let tenths = Int((clamped * 10).rounded(.down)) % 10
        return String(format: "%02d:%02d.%d", minutes, wholeSeconds, tenths)
    }

    static func duration(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    static func rulerMinute(_ minute: Int) -> String {
        String(format: "%02d:00", minute)
    }
}
private struct TimelineVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TimelineVideoPlayerContainerView {
        let view = TimelineVideoPlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: TimelineVideoPlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class TimelineVideoPlayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct TimelineImportedMovie: Transferable, Sendable {
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            guard let url = VideoStorage.url(named: movie.fileName) else {
                throw TimelineVideoImportError.unavailable
            }
            return SentTransferredFile(url)
        } importing: { receivedFile in
            let fileName = try VideoStorage.save(from: receivedFile.file) { fraction, copiedBytes, totalBytes in
                NotificationCenter.default.post(
                    name: .videoStorageCopyProgress,
                    object: nil,
                    userInfo: [
                        "fraction": fraction,
                        "copiedBytes": copiedBytes,
                        "totalBytes": totalBytes
                    ]
                )
            }
            return TimelineImportedMovie(fileName: fileName)
        }
    }
}

private enum TimelineVideoImportError: Error {
    case unavailable
}

private struct TimelineMatchClockSettings: Codable, Equatable {
    var firstHalfSeconds: Int
    var secondHalfSeconds: Int
    var stoppages: [TimelineMatchClockStop]

    static let standard = TimelineMatchClockSettings(
        firstHalfSeconds: 40 * 60,
        secondHalfSeconds: 40 * 60,
        stoppages: []
    )

    func clockDuration(for half: Int) -> Int {
        half >= 1 ? secondHalfSeconds : firstHalfSeconds
    }

    mutating func setClockDuration(_ seconds: Int, for half: Int) {
        if half >= 1 {
            secondHalfSeconds = seconds
        } else {
            firstHalfSeconds = seconds
        }
        self = normalized()
    }

    func totalStoppageSeconds(for half: Int) -> Int {
        stoppages
            .filter { $0.half == normalizedHalf(half) }
            .reduce(0) { $0 + max(0, $1.durationSeconds) }
    }

    func actualHalfTimelineDuration(for half: Int) -> Int {
        clockDuration(for: half) + totalStoppageSeconds(for: half)
    }

    func stoppagesForTimelineScope(_ half: Int?) -> [TimelineMatchClockStop] {
        stoppages
            .filter { stop in half == nil || stop.half == half }
            .sorted { lhs, rhs in
                if lhs.half != rhs.half { return lhs.half < rhs.half }
                if lhs.clockSecond != rhs.clockSecond { return lhs.clockSecond < rhs.clockSecond }
                return lhs.durationSeconds < rhs.durationSeconds
            }
    }

    func timelineSecond(forClockSecond clockSecond: Int, half: Int) -> Int {
        let half = normalizedHalf(half)
        let clampedClockSecond = min(max(0, clockSecond), clockDuration(for: half))
        let stoppageSecondsBefore = stoppagesForTimelineScope(half)
            .filter { $0.clockSecond < clampedClockSecond }
            .reduce(0) { $0 + max(0, $1.durationSeconds) }
        return clampedClockSecond + stoppageSecondsBefore
    }

    func clockSecond(fromTimelineSecond timelineSecond: Int, half: Int) -> Int {
        let half = normalizedHalf(half)
        let clampedTimelineSecond = min(max(0, timelineSecond), actualHalfTimelineDuration(for: half))
        var elapsedStoppageSeconds = 0

        for stoppage in stoppagesForTimelineScope(half) {
            let stopStart = stoppage.clockSecond + elapsedStoppageSeconds
            let stopEnd = stopStart + stoppage.durationSeconds
            if clampedTimelineSecond < stopStart {
                return min(clockDuration(for: half), max(0, clampedTimelineSecond - elapsedStoppageSeconds))
            }
            if clampedTimelineSecond <= stopEnd {
                return stoppage.clockSecond
            }
            elapsedStoppageSeconds += stoppage.durationSeconds
        }

        return min(clockDuration(for: half), max(0, clampedTimelineSecond - elapsedStoppageSeconds))
    }

    func normalized() -> TimelineMatchClockSettings {
        let firstHalfSeconds = min(max(60, firstHalfSeconds), 80 * 60)
        let secondHalfSeconds = min(max(60, secondHalfSeconds), 80 * 60)
        let normalizedStoppages = stoppages.map { stoppage in
            let half = normalizedHalf(stoppage.half)
            let clockDuration = half == 0 ? firstHalfSeconds : secondHalfSeconds
            return TimelineMatchClockStop(
                id: stoppage.id,
                half: half,
                clockSecond: min(max(0, stoppage.clockSecond), clockDuration),
                durationSeconds: min(max(1, stoppage.durationSeconds), 20 * 60)
            )
        }
        .sorted { lhs, rhs in
            if lhs.half != rhs.half { return lhs.half < rhs.half }
            if lhs.clockSecond != rhs.clockSecond { return lhs.clockSecond < rhs.clockSecond }
            return lhs.durationSeconds < rhs.durationSeconds
        }

        return TimelineMatchClockSettings(
            firstHalfSeconds: firstHalfSeconds,
            secondHalfSeconds: secondHalfSeconds,
            stoppages: normalizedStoppages
        )
    }

    private func normalizedHalf(_ half: Int) -> Int {
        half >= 1 ? 1 : 0
    }
}

private struct TimelineMatchClockStop: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var half: Int
    var clockSecond: Int
    var durationSeconds: Int
}

// 試合削除時に、その試合の時計設定だけを消すための公開ヘルパー。
// 値の型(非公開)に触れずに、保存領域から該当試合のキーだけ取り除く。
enum MatchClockSettingsCleanup {
    // TimelineMatchClockStorage と同じ保存キー
    private static let storageKey = "matchClockSettingsByMatchID"

    static func removeSettings(for matchID: UUID) {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        map.removeValue(forKey: matchID.uuidString)
        if map.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else if let newData = try? JSONSerialization.data(withJSONObject: map) {
            UserDefaults.standard.set(newData, forKey: storageKey)
        }
    }
}

private enum TimelineMatchClockStorage {
    private static let storageKey = "matchClockSettingsByMatchID"

    static func settings(for matchID: UUID) -> TimelineMatchClockSettings {
        settingsMap()[matchID.uuidString]?.normalized() ?? .standard
    }

    static func setSettings(_ settings: TimelineMatchClockSettings, for matchID: UUID) {
        var map = settingsMap()
        let normalizedSettings = settings.normalized()
        if normalizedSettings == .standard {
            map.removeValue(forKey: matchID.uuidString)
        } else {
            map[matchID.uuidString] = normalizedSettings
        }

        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func settingsMap() -> [String: TimelineMatchClockSettings] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: TimelineMatchClockSettings].self, from: data) else {
            return [:]
        }
        return map
    }
}

private struct MatchClockSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialSettings: TimelineMatchClockSettings
    let currentTimelineSecond: Double
    let currentHalf: Int?
    let secondHalfTimelineOffset: Int
    let onSave: (TimelineMatchClockSettings) -> Void

    @State private var draft: TimelineMatchClockSettings

    init(
        initialSettings: TimelineMatchClockSettings,
        currentTimelineSecond: Double,
        currentHalf: Int?,
        secondHalfTimelineOffset: Int,
        onSave: @escaping (TimelineMatchClockSettings) -> Void
    ) {
        self.initialSettings = initialSettings
        self.currentTimelineSecond = currentTimelineSecond
        self.currentHalf = currentHalf
        self.secondHalfTimelineOffset = secondHalfTimelineOffset
        self.onSave = onSave
        _draft = State(initialValue: initialSettings.normalized())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(Color.secondary.opacity(0.32))
                    .frame(width: 72, height: 5)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("試合時計")
                            .font(.title2.weight(.black))
                        Text("前後半の長さと停止区間")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("閉じる") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.blue)
                }

                section("形式") {
                    HStack(spacing: 8) {
                        presetButton("15人制 40分", seconds: 40 * 60)
                        presetButton("7人制 7分", seconds: 7 * 60)
                    }
                }

                section("前後半") {
                    halfDurationEditor(title: "前半", half: 0)
                    halfDurationEditor(title: "後半", half: 1)
                }

                section("停止区間") {
                    Button {
                        addStopAtCurrentPosition()
                    } label: {
                        Label("現在位置で停止を追加", systemImage: "plus.circle.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    if draft.stoppages.isEmpty {
                        Text("停止区間なし")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(draft.stoppagesForTimelineScope(nil)) { stoppage in
                                stoppageRow(stoppage)
                            }
                        }
                    }
                }

                Button {
                    onSave(draft.normalized())
                    dismiss()
                } label: {
                    Label("保存", systemImage: "checkmark.circle.fill")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func presetButton(_ title: String, seconds: Int) -> some View {
        Button {
            draft.firstHalfSeconds = seconds
            draft.secondHalfSeconds = seconds
            draft = draft.normalized()
        } label: {
            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func halfDurationEditor(title: String, half: Int) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline.weight(.black))
                .frame(width: 52, alignment: .leading)

            Text(Self.timeText(draft.clockDuration(for: half)))
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .frame(width: 96, alignment: .leading)

            Spacer(minLength: 4)

            smallButton("-1分", color: .orange) {
                adjustHalfDuration(half: half, delta: -60)
            }

            smallButton("+1分", color: .blue) {
                adjustHalfDuration(half: half, delta: 60)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func stoppageRow(_ stoppage: TimelineMatchClockStop) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(halfLabel(stoppage.half)) {
                    updateStoppage(stoppage) { item in
                        item.half = item.half == 0 ? 1 : 0
                    }
                }
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.blue)
                .clipShape(Capsule())

                Text(Self.timeText(stoppage.clockSecond))
                    .font(.headline.weight(.black).monospacedDigit())

                Text("+\(Self.timeText(stoppage.durationSeconds))")
                    .font(.headline.weight(.black).monospacedDigit())
                    .foregroundStyle(.orange)

                Spacer()

                Button(role: .destructive) {
                    draft.stoppages.removeAll { $0.id == stoppage.id }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.headline.weight(.bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                smallButton("-10秒", color: .orange) {
                    adjustStoppageClock(stoppage, delta: -10)
                }
                smallButton("+10秒", color: .blue) {
                    adjustStoppageClock(stoppage, delta: 10)
                }
                smallButton("-停止", color: .orange) {
                    adjustStoppageDuration(stoppage, delta: -10)
                }
                smallButton("+停止", color: .blue) {
                    adjustStoppageDuration(stoppage, delta: 10)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func smallButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.black).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func adjustHalfDuration(half: Int, delta: Int) {
        draft.setClockDuration(draft.clockDuration(for: half) + delta, for: half)
    }

    private func addStopAtCurrentPosition() {
        let half: Int
        let localTimelineSecond: Int

        if let currentHalf {
            half = currentHalf
            localTimelineSecond = max(0, Int(currentTimelineSecond.rounded()))
        } else if currentTimelineSecond >= Double(secondHalfTimelineOffset) {
            half = 1
            localTimelineSecond = max(0, Int((currentTimelineSecond - Double(secondHalfTimelineOffset)).rounded()))
        } else {
            half = 0
            localTimelineSecond = max(0, Int(currentTimelineSecond.rounded()))
        }

        let clockSecond = draft.clockSecond(fromTimelineSecond: localTimelineSecond, half: half)
        draft.stoppages.append(
            TimelineMatchClockStop(
                half: half,
                clockSecond: clockSecond,
                durationSeconds: 30
            )
        )
        draft = draft.normalized()
    }

    private func adjustStoppageClock(_ stoppage: TimelineMatchClockStop, delta: Int) {
        updateStoppage(stoppage) { item in
            item.clockSecond += delta
        }
    }

    private func adjustStoppageDuration(_ stoppage: TimelineMatchClockStop, delta: Int) {
        updateStoppage(stoppage) { item in
            item.durationSeconds += delta
        }
    }

    private func updateStoppage(
        _ stoppage: TimelineMatchClockStop,
        transform: (inout TimelineMatchClockStop) -> Void
    ) {
        guard let index = draft.stoppages.firstIndex(where: { $0.id == stoppage.id }) else { return }
        transform(&draft.stoppages[index])
        draft = draft.normalized()
    }

    private func halfLabel(_ half: Int) -> String {
        half >= 1 ? "後半" : "前半"
    }

    private static func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}


#Preview {
    NavigationStack {
        TimelineEditorView(match: Match(tournamentID: UUID(), homeTeamID: UUID(), awayTeamID: UUID(), playedAt: Date()))
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
