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

private struct TimelineRulerContentIdentity: Hashable {
    let durationTicks: Int
}

private struct TimelineTracksContentIdentity: Hashable {
    let durationTicks: Int
    let visibleTracks: [TimelineTrackType]
    let clips: [TimelineClipContentIdentity]
    let matchSegments: [MatchSegmentContentIdentity]
    let videoSegments: [VideoSegmentContentIdentity]
    let selectedClipID: UUID?
    let selectedVideoSegmentID: UUID?
}

private struct TimelineClipContentIdentity: Hashable {
    let id: UUID
    let trackType: TimelineTrackType
    let startTicks: Int
    let endTicks: Int
    let title: String
    let isSelected: Bool
}

private struct MatchSegmentContentIdentity: Hashable {
    let id: UUID
    let halfType: String
    let startTicks: Int
    let endTicks: Int
    let displayLabel: String
}

private struct VideoSegmentContentIdentity: Hashable {
    let id: UUID
    let sourceName: String
    let startTicks: Int
    let endTicks: Int
    let fileName: String?
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
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var isScrubbingTimeline = false
    @State private var isMatchClockSettingsPresented = false
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
                        onExport: { }
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
                        timelineScrollOffset: $timelineScrollOffset,
                        isScrubbingTimeline: $isScrubbingTimeline,
                        selectedPlaybackTrack: selectedPlaybackTrack,
                        onSelectVideoSegment: { segment in
                            selectVideoSegment(segment, autoplay: false)
                        },
                        onAddClipForTrack: { trackType in
                            handleToolTap(trackType)
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
        guard abs(viewModel.currentVideoTime - clampedTime) > 0.05 else { return }

        // 指でスクラブしたら連続再生モードは解除して通常操作に戻す
        clearSequentialPlayback()

        viewModel.currentVideoTime = clampedTime
        videoPlayer?.pause()
        viewModel.isPlaying = false
        seekPlayerToCurrentTime(selectingSegmentAtCurrentTime: true)
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

private struct RugbyPitchMock: View {
    private let players: [(CGFloat, CGFloat, Color)] = [
        (0.24, 0.30, .white), (0.31, 0.42, .red), (0.38, 0.52, .white),
        (0.47, 0.43, .orange), (0.54, 0.50, .orange), (0.61, 0.39, .orange),
        (0.68, 0.31, .orange), (0.73, 0.58, .orange), (0.40, 0.28, .white),
        (0.58, 0.25, .white), (0.18, 0.62, .orange), (0.82, 0.46, .white)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    Rectangle()
                        .fill(Color.white.opacity(index == 2 ? 0.12 : 0.07))
                        .frame(width: 1.2)
                        .position(
                            x: proxy.size.width * CGFloat(index + 1) / 6,
                            y: proxy.size.height / 2
                        )
                }

                ForEach(0..<4, id: \.self) { index in
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .position(
                            x: proxy.size.width / 2,
                            y: proxy.size.height * CGFloat(index + 1) / 5
                        )
                }

                ForEach(players.indices, id: \.self) { index in
                    let player = players[index]
                    Circle()
                        .fill(player.2)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 3)
                        .position(x: proxy.size.width * player.0, y: proxy.size.height * player.1)
                }
            }
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

struct TimelineRulerView: View {
    var duration: Double

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let minuteCount = max(1, Int(duration / 60))

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.035))

                ForEach(0...minuteCount, id: \.self) { minute in
                    let isMajor = minute % 5 == 0
                    let x = min(width, width * CGFloat(Double(minute * 60) / duration))

                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.42 : 0.20))
                        .frame(width: isMajor ? 1.2 : 1, height: isMajor ? 34 : 18)
                        .position(x: x, y: isMajor ? 28 : 36)

                    if isMajor {
                        Text(TimelineTimeFormat.rulerMinute(minute))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.70))
                            .monospacedDigit()
                            .position(x: min(max(26, x), width - 28), y: 11)
                    }
                }
            }
        }
    }
}

struct TimelineTracksView: View {
    @ObservedObject var viewModel: TimelineEditorViewModel
    @Binding var timelineScrollOffset: CGFloat
    @Binding var isScrubbingTimeline: Bool
    var selectedPlaybackTrack: TimelineTrackType?
    var onSelectVideoSegment: (VideoSegment) -> Void
    var onAddClipForTrack: (TimelineTrackType) -> Void
    var onTrackLabelTap: (TimelineTrackType) -> Void
    var onAdjustSelectedStart: (Double) -> Void
    var onAdjustSelectedEnd: (Double) -> Void
    var onTimelineTimeChanged: (Double) -> Void

    private let labelWidth: CGFloat = 110
    private let rulerHeight: CGFloat = 42
    private let rowHeight: CGFloat = 48

    private var rulerContentIdentity: AnyHashable {
        AnyHashable(TimelineRulerContentIdentity(durationTicks: Self.timeTicks(viewModel.videoDuration)))
    }

    private var tracksContentIdentity: AnyHashable {
        AnyHashable(
            TimelineTracksContentIdentity(
                durationTicks: Self.timeTicks(viewModel.videoDuration),
                visibleTracks: viewModel.visibleTracks,
                clips: viewModel.timelineClips.map { clip in
                    TimelineClipContentIdentity(
                        id: clip.id,
                        trackType: clip.trackType,
                        startTicks: Self.timeTicks(clip.startTime),
                        endTicks: Self.timeTicks(clip.endTime),
                        title: clip.title,
                        isSelected: clip.isSelected
                    )
                },
                matchSegments: viewModel.matchSegments.map { segment in
                    MatchSegmentContentIdentity(
                        id: segment.id,
                        halfType: segment.halfType.rawValue,
                        startTicks: Self.timeTicks(segment.startTime),
                        endTicks: Self.timeTicks(segment.endTime),
                        displayLabel: segment.displayLabel
                    )
                },
                videoSegments: viewModel.videoSegments.map { segment in
                    VideoSegmentContentIdentity(
                        id: segment.id,
                        sourceName: segment.sourceName,
                        startTicks: Self.timeTicks(segment.startTime),
                        endTicks: Self.timeTicks(segment.endTime),
                        fileName: segment.fileName
                    )
                },
                selectedClipID: viewModel.selectedClipID,
                selectedVideoSegmentID: viewModel.selectedVideoSegmentID
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let timelineViewportWidth = max(1, proxy.size.width - labelWidth)
            let timelineCanvasWidth = max(timelineViewportWidth, CGFloat(viewModel.videoDuration) * 1.55)
            let fixedPlayheadX = proxy.size.width / 2
            let playheadTimelineX = max(0, fixedPlayheadX - labelWidth)
            let leadingInset = playheadTimelineX
            let trailingInset = max(0, timelineViewportWidth - playheadTimelineX)
            let scrollableContentWidth = leadingInset + timelineCanvasWidth + trailingInset
            let rowsHeight = CGFloat(viewModel.visibleTracks.count) * rowHeight

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.01, green: 0.05, blue: 0.10).opacity(0.90))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.11), lineWidth: 1)
                    )

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: labelWidth, height: rulerHeight)

                        TimelineHorizontalOffsetScrollView(
                            offset: $timelineScrollOffset,
                            isTracking: $isScrubbingTimeline,
                            contentWidth: scrollableContentWidth,
                            contentIdentity: rulerContentIdentity,
                            showsIndicators: false
                        ) {
                            HStack(spacing: 0) {
                                Color.clear.frame(width: leadingInset)
                                TimelineRulerView(duration: viewModel.videoDuration)
                                    .frame(width: timelineCanvasWidth, height: rulerHeight)
                                Color.clear.frame(width: trailingInset)
                            }
                        }
                        .frame(width: timelineViewportWidth, height: rulerHeight)
                    }

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

                            TimelineHorizontalOffsetScrollView(
                                offset: $timelineScrollOffset,
                                isTracking: $isScrubbingTimeline,
                                contentWidth: scrollableContentWidth,
                                contentIdentity: tracksContentIdentity,
                                showsIndicators: true
                            ) {
                                HStack(spacing: 0) {
                                    Color.clear.frame(width: leadingInset)
                                    VStack(spacing: 0) {
                                        ForEach(viewModel.visibleTracks) { trackType in
                                            TimelineTrackRowView(
                                                trackType: trackType,
                                                duration: viewModel.videoDuration,
                                                rowHeight: rowHeight,
                                                clips: viewModel.timelineClips.filter { $0.trackType == trackType },
                                                matchSegments: viewModel.matchSegments,
                                                videoSegments: viewModel.videoSegments,
                                                selectedClipID: viewModel.selectedClipID,
                                                selectedVideoSegmentID: viewModel.selectedVideoSegmentID,
                                                showsLabel: false,
                                                onSelectClip: { clipID in
                                                    viewModel.selectClip(clipID)
                                                },
                                                onSelectVideoSegment: { segment in
                                                    onSelectVideoSegment(segment)
                                                },
                                                onRowTap: { rowTrackType in
                                                    if viewModel.selectedTool == rowTrackType {
                                                        onAddClipForTrack(rowTrackType)
                                                    }
                                                },
                                                onAdjustSelectedStart: { delta in
                                                    onAdjustSelectedStart(delta)
                                                },
                                                onAdjustSelectedEnd: { delta in
                                                    onAdjustSelectedEnd(delta)
                                                }
                                            )
                                            .frame(width: timelineCanvasWidth, height: rowHeight)
                                        }
                                    }
                                    .frame(width: timelineCanvasWidth, height: rowsHeight)
                                    Color.clear.frame(width: trailingInset)
                                }
                            }
                            .frame(width: timelineViewportWidth, height: rowsHeight)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Rectangle()
                    .fill(Color.blue.opacity(0.70))
                    .frame(width: 1)
                    .position(x: labelWidth, y: proxy.size.height / 2)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
                    .position(x: fixedPlayheadX, y: proxy.size.height / 2)
                    .allowsHitTesting(false)

                if viewModel.videoSegments.isEmpty {
                    Text("動画を追加すると、ここに実際のクリップが表示されます")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.36))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: timelineViewportWidth - 24)
                        .position(x: labelWidth + timelineViewportWidth / 2, y: rulerHeight + rowHeight / 2)
                        .allowsHitTesting(false)
                }

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
                .position(x: fixedPlayheadX, y: proxy.size.height / 2 + 6)
                .allowsHitTesting(false)
            }
            .onAppear {
                timelineScrollOffset = offset(
                    for: viewModel.currentVideoTime,
                    duration: viewModel.videoDuration,
                    timelineCanvasWidth: timelineCanvasWidth,
                    scrollableContentWidth: scrollableContentWidth,
                    timelineViewportWidth: timelineViewportWidth
                )
            }
            .onChange(of: viewModel.currentVideoTime) { _, newTime in
                guard !isScrubbingTimeline else { return }
                timelineScrollOffset = offset(
                    for: newTime,
                    duration: viewModel.videoDuration,
                    timelineCanvasWidth: timelineCanvasWidth,
                    scrollableContentWidth: scrollableContentWidth,
                    timelineViewportWidth: timelineViewportWidth
                )
            }
            .onChange(of: timelineScrollOffset) { _, newOffset in
                guard isScrubbingTimeline else { return }
                onTimelineTimeChanged(
                    time(
                        for: newOffset,
                        duration: viewModel.videoDuration,
                        timelineCanvasWidth: timelineCanvasWidth
                    )
                )
            }
        }
    }

    private func offset(
        for time: Double,
        duration: Double,
        timelineCanvasWidth: CGFloat,
        scrollableContentWidth: CGFloat,
        timelineViewportWidth: CGFloat
    ) -> CGFloat {
        let rawOffset = CGFloat(min(max(0, time), duration) / max(1, duration)) * timelineCanvasWidth
        let maxOffset = max(0, scrollableContentWidth - timelineViewportWidth)
        return min(max(0, rawOffset), maxOffset)
    }

    private func time(for offset: CGFloat, duration: Double, timelineCanvasWidth: CGFloat) -> Double {
        let progress = Double(min(max(0, offset), timelineCanvasWidth) / max(1, timelineCanvasWidth))
        return min(max(0, progress * duration), duration)
    }

    private static func timeTicks(_ seconds: Double) -> Int {
        Int((seconds * 10).rounded())
    }
}

private struct TimelineHorizontalOffsetScrollView<Content: View>: UIViewRepresentable {
    @Binding var offset: CGFloat
    @Binding var isTracking: Bool
    var contentWidth: CGFloat
    var contentIdentity: AnyHashable = 0
    var showsIndicators: Bool
    @ViewBuilder var content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator(offset: $offset, isTracking: $isTracking)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = showsIndicators
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = true
        scrollView.delaysContentTouches = false

        let host = UIHostingController(rootView: hostedContent)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(host.view)

        let widthConstraint = host.view.widthAnchor.constraint(equalToConstant: contentWidth)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            host.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            widthConstraint
        ])

        context.coordinator.host = host
        context.coordinator.widthConstraint = widthConstraint
        context.coordinator.lastHostedContentKey = hostedContentKey
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // この中で setContentOffset 等を行うと delegate が同期的に呼ばれる。
        // 「SwiftUIの画面更新中に状態を変更」する警告(未定義動作)を防ぐため、
        // 更新中フラグを立てて delegate 側の状態書き込みを遅延させる。
        context.coordinator.isPerformingViewUpdate = true
        defer { context.coordinator.isPerformingViewUpdate = false }

        let contentKey = hostedContentKey
        if context.coordinator.lastHostedContentKey != contentKey {
            context.coordinator.host?.rootView = hostedContent
            context.coordinator.lastHostedContentKey = contentKey
        }
        context.coordinator.widthConstraint?.constant = contentWidth
        scrollView.showsHorizontalScrollIndicator = showsIndicators
        scrollView.alwaysBounceHorizontal = contentWidth > scrollView.bounds.width

        let maxOffset = max(0, contentWidth - scrollView.bounds.width)
        let clampedOffset = min(max(0, offset), maxOffset)
        if abs(scrollView.contentOffset.x - clampedOffset) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: clampedOffset, y: 0), animated: false)
        }
    }

    private var hostedContent: AnyView {
        AnyView(content.frame(width: contentWidth))
    }

    private var hostedContentKey: HostedContentKey {
        HostedContentKey(
            identity: contentIdentity,
            contentWidth: Int(max(1, contentWidth).rounded())
        )
    }

    struct HostedContentKey: Equatable {
        let identity: AnyHashable
        let contentWidth: Int
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var offset: CGFloat
        @Binding var isTracking: Bool
        var host: UIHostingController<AnyView>?
        var widthConstraint: NSLayoutConstraint?
        var lastHostedContentKey: HostedContentKey?
        // updateUIView 実行中(=SwiftUIの画面更新中)は true。
        // この間の状態書き込みは次のタイミングへ遅らせる。
        var isPerformingViewUpdate = false

        init(offset: Binding<CGFloat>, isTracking: Binding<Bool>) {
            _offset = offset
            _isTracking = isTracking
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            setIsTracking(true)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if isPerformingViewUpdate {
                DispatchQueue.main.async { [weak self, weak scrollView] in
                    guard let self, let scrollView else { return }
                    self.offset = scrollView.contentOffset.x
                }
            } else {
                offset = scrollView.contentOffset.x
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
                    self?.isTracking = value
                }
            } else {
                isTracking = value
            }
        }
    }
}

struct TimelineTrackRowView: View {
    var trackType: TimelineTrackType
    var duration: Double
    var rowHeight: CGFloat
    var clips: [TimelineClip]
    var matchSegments: [MatchSegment]
    var videoSegments: [VideoSegment]
    var selectedClipID: UUID?
    var selectedVideoSegmentID: UUID?
    var showsLabel: Bool = true
    var onSelectClip: (UUID) -> Void
    var onSelectVideoSegment: (VideoSegment) -> Void
    var onRowTap: (TimelineTrackType) -> Void
    var onAdjustSelectedStart: (Double) -> Void
    var onAdjustSelectedEnd: (Double) -> Void

    private let labelWidth: CGFloat = 110
    @GestureState private var resizePreview: ClipResizePreview = .inactive

    var body: some View {
        HStack(spacing: 0) {
            if showsLabel {
                TimelineTrackLabelView(trackType: trackType)
                    .frame(width: labelWidth)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(trackType == .video || trackType == .match ? Color.white.opacity(0.030) : Color.clear)

                    TimelineGrid(duration: duration)

                    switch trackType {
                    case .video:
                        videoClips(width: proxy.size.width)
                    case .match:
                        matchClips(width: proxy.size.width)
                    default:
                        eventClips(width: proxy.size.width)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onRowTap(trackType)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
    }

    private func eventClips(width: CGFloat) -> some View {
        ForEach(clips) { clip in
            let times = displayedTimes(for: clip)
            let block = blockFrame(start: times.start, end: times.end, width: width)
            ZStack {
                HStack(spacing: 6) {
                    Text(clip.title)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: 0)
                    if clip.id == selectedClipID {
                        HStack(spacing: 3) {
                            Capsule().fill(Color.white.opacity(0.82)).frame(width: 3, height: 22)
                            Capsule().fill(Color.white.opacity(0.82)).frame(width: 3, height: 22)
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(width: block.width, height: rowHeight - 18)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(clip.color.gradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            clip.id == selectedClipID ? Color.white : clip.color.opacity(0.85),
                            lineWidth: clip.id == selectedClipID ? 2 : 1
                        )
                )
                .shadow(
                    color: clip.id == selectedClipID ? clip.color.opacity(0.60) : Color.clear,
                    radius: 10
                )

                if clip.id == selectedClipID {
                    HStack {
                        TimelineClipResizeHandle()
                            .highPriorityGesture(
                                resizeGesture(edge: .start, width: width)
                            )

                        Spacer(minLength: 0)

                        TimelineClipResizeHandle()
                            .highPriorityGesture(
                                resizeGesture(edge: .end, width: width)
                            )
                    }
                    .padding(.horizontal, 4)
                    .frame(width: block.width, height: rowHeight - 18)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .highPriorityGesture(TapGesture().onEnded {
                onSelectClip(clip.id)
            })
            .position(x: block.midX, y: rowHeight / 2)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private func videoClips(width: CGFloat) -> some View {
        ForEach(videoSegments) { segment in
            let block = blockFrame(start: segment.startTime, end: segment.endTime, width: width)
            HStack(spacing: 8) {
                Image(systemName: "film.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.white.opacity(0.60), lineWidth: 1)
                    )

                Text(segment.sourceName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: block.width, height: rowHeight - 16)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(trackType.color.gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(segment.id == selectedVideoSegmentID ? Color.white : Color.white.opacity(0.32), lineWidth: segment.id == selectedVideoSegmentID ? 2 : 1)
            )
            .shadow(color: segment.id == selectedVideoSegmentID ? trackType.color.opacity(0.55) : .clear, radius: 8)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .highPriorityGesture(TapGesture().onEnded {
                onSelectVideoSegment(segment)
            })
            .position(x: block.midX, y: rowHeight / 2)
        }
    }

    private func matchClips(width: CGFloat) -> some View {
        let sortedSegments = matchSegments.sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
            return lhs.endTime < rhs.endTime
        }

        return ZStack(alignment: .leading) {
            ForEach(Array(sortedSegments.indices.dropLast()), id: \.self) { index in
                let current = sortedSegments[index]
                let next = sortedSegments[index + 1]
                if next.startTime > current.endTime {
                    let gap = blockFrame(start: current.endTime, end: next.startTime, width: width)
                    let label = current.halfType == next.halfType ? "停止" : "中断"

                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.26), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .frame(width: gap.width, height: rowHeight - 24)
                        .overlay(
                            Text(label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.58))
                        )
                        .position(x: gap.midX, y: rowHeight / 2)
                }
            }

            ForEach(sortedSegments) { segment in
                let block = blockFrame(start: segment.startTime, end: segment.endTime, width: width)
                HStack(spacing: 8) {
                    Circle()
                        .fill(trackType.color)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1))

                    Text(segment.displayLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(width: block.width, height: rowHeight - 18)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [trackType.color.opacity(0.48), trackType.color.opacity(0.18)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(trackType.color.opacity(0.95), lineWidth: 1)
                )
                .position(x: block.midX, y: rowHeight / 2)
            }
        }
    }

    private func blockFrame(start: Double, end: Double, width: CGFloat) -> (midX: CGFloat, width: CGFloat) {
        let startX = width * CGFloat(max(0, min(duration, start)) / max(1, duration))
        let endX = width * CGFloat(max(0, min(duration, end)) / max(1, duration))
        let blockWidth = max(34, endX - startX)
        return (startX + blockWidth / 2, blockWidth)
    }

    private func displayedTimes(for clip: TimelineClip) -> (start: Double, end: Double) {
        var start = clip.startTime
        var end = clip.endTime

        guard clip.id == selectedClipID else {
            return (start, end)
        }

        switch resizePreview.edge {
        case .start:
            start = min(max(0, start + resizePreview.delta), end - 1)
        case .end:
            end = max(min(duration, end + resizePreview.delta), start + 1)
        case .none:
            break
        }

        return (start, end)
    }

    private func resizeGesture(edge: ClipResizeEdge, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($resizePreview) { value, state, _ in
                state = ClipResizePreview(edge: edge, delta: resizeDelta(for: value.translation.width, width: width))
            }
            .onEnded { value in
                let delta = resizeDelta(for: value.translation.width, width: width)
                switch edge {
                case .start:
                    onAdjustSelectedStart(delta)
                case .end:
                    onAdjustSelectedEnd(delta)
                }
            }
    }

    private func resizeDelta(for translation: CGFloat, width: CGFloat) -> Double {
        Double(translation / max(1, width)) * duration
    }

    private enum ClipResizeEdge: Equatable {
        case start
        case end
    }

    private struct ClipResizePreview: Equatable {
        var edge: ClipResizeEdge?
        var delta: Double

        static let inactive = ClipResizePreview(edge: nil, delta: 0)
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
            .contentShape(Rectangle())
    }
}

private struct TimelineGrid: View {
    var duration: Double

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let minuteCount = max(1, Int(duration / 60))

            ZStack(alignment: .leading) {
                ForEach(0...minuteCount, id: \.self) { minute in
                    if minute % 5 == 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 1)
                            .position(
                                x: min(width, width * CGFloat(Double(minute * 60) / duration)),
                                y: proxy.size.height / 2
                            )
                    }
                }
            }
        }
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

struct LegacyTimelineEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let match: Match

    @State private var selectedScope: TimelineScope = .all
    @State private var selectedEvent: StatEvent?
    @State private var selectedTimelineEventID: UUID?
    @State private var isAddEventSheetPresented = false
    @State private var categoryPendingAddition: TimelineEventCategory = .tryScore
    @State private var isDeleteConfirmationPresented = false
    @State private var eventPendingDeletion: TimelineDeletionCandidate?
    @State private var events: [StatEvent] = []
    @State private var players: [Player] = []
    @State private var teams: [Team] = []
    @State private var didLoad = false
    @State private var saveErrorMessage: String?
    @State private var timelineZoom: CGFloat = 0.035
    @State private var baseTimelineZoom: CGFloat = 0.035
    @State private var isEventListExpanded = false
    @State private var pendingTimelineSaveTask: Task<Void, Never>?
    @State private var timelinePlaybackTask: Task<Void, Never>?
    @State private var isTimelinePlaying = false
    @State private var timelineViewportFrame: CGRect = .zero
    @State private var timelineAutoScrollAccumulatedPixels: CGFloat = 0
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var timelineAutoScrollTask: Task<Void, Never>?
    @State private var timelineAutoScrollDirection = 0
    @State private var timelineAutoScrollMaxSeconds = 0
    @State private var timelineAutoScrollIntensity: CGFloat = 0
    @State private var timelinePresentation = TimelinePresentationState.empty
    @State private var timelinePresentationVersion = 0
    @State private var timelineRenderOffset: CGFloat = 0
    @State private var timelineRenderedViewportWidth: CGFloat = 0
    @State private var timelineRenderWindow = TimelineRenderWindow.empty
    @State private var timelineAvailableViewportWidth: CGFloat = 0
    @State private var isTimelineScrollSyncSuppressed = false
    @State private var isTimelineOverviewMode = true
    @State private var playheadTimelineSecond: Double = 0
    @State private var didSetInitialPlayheadPosition = false
    @State private var videoPlayer: AVPlayer?
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var isVideoImporting = false
    @State private var isVideoDeleteConfirmationPresented = false
    @State private var isMatchClockSettingsPresented = false
    @State private var matchClockSettings = TimelineMatchClockSettings.standard
    @State private var importedVideoClips: [TimelineVideoClip] = []
    @State private var selectedVideoClipID: String?
    @State private var activeVideoClipID: String?
    @State private var videoClipPendingDeletion: TimelineVideoClip?
    @State private var videoClipLoadingTask: Task<Void, Never>?
    @State private var pendingScrollSeekTask: Task<Void, Never>?
    @State private var videoImportProgress: Double = 0
    @State private var videoImportCopiedBytes: Int64 = 0
    @State private var videoImportTotalBytes: Int64 = 0
    @State private var videoImportStartedAt: Date?
    @State private var videoImportCurrentIndex = 0
    @State private var videoImportTotalCount = 0

    private let minimumTimelineZoom: CGFloat = 0.035
    private let maximumTimelineZoom: CGFloat = 10.0
    private let resizeSensitivity: CGFloat = 1.35
    private let timelineAutoScrollEdgeInset: CGFloat = 76
    private let timelineAutoScrollStep: CGFloat = 34
    private let timelineTrackLabelWidth: CGFloat = 96
    private let timelineRulerHeight: CGFloat = 44
    private let timelineTrackRowHeight: CGFloat = 42
    private let timelineTimeRowCount = 2
    private let timelineRenderBucketWidth: CGFloat = 720
    private let timelineRenderPadding: CGFloat = 960
    private let defaultHalfTimelineSeconds = 40 * 60
    private let trackDefinitions: [TimelineTrackDefinition] = [
        TimelineTrackDefinition(title: "HOME", systemImage: "house.fill", color: .timelineHome) { event, match in
            event.category == "possession" && (event.teamID == match.homeTeamID || (event.teamID == nil && event.outcome == "own"))
        },
        TimelineTrackDefinition(title: "AWAY", systemImage: "a.circle.fill", color: .timelineAway) { event, match in
            event.category == "possession" && (event.teamID == match.awayTeamID || (event.teamID == nil && event.outcome == "opponent"))
        },
        TimelineTrackDefinition(title: "BIP", systemImage: "clock.fill", color: .timelineBIP) { event, _ in
            event.category == "possession" && event.outcome == "none"
        },
        TimelineTrackDefinition(title: "TRY", systemImage: "rugbyball.fill", color: .timelineTry) { event, _ in
            event.category == "try"
        },
        TimelineTrackDefinition(title: "CONV", systemImage: "figure.rugby", color: .timelineConversion) { event, _ in
            event.category == "conversion"
        },
        TimelineTrackDefinition(title: "PG", systemImage: "p.circle.fill", color: .timelineKick) { event, _ in
            event.category == "penalty_goal"
        },
        TimelineTrackDefinition(title: "DG", systemImage: "d.circle.fill", color: .timelineKick) { event, _ in
            event.category == "drop_goal"
        },
        TimelineTrackDefinition(title: "LO", systemImage: "figure.strengthtraining.traditional", color: .timelineLineout) { event, _ in
            event.category == "lineout"
        },
        TimelineTrackDefinition(title: "SCR", systemImage: "person.3.fill", color: .timelineScrum) { event, _ in
            event.category == "scrum"
        }
    ]

    private enum TimelineScope: String, CaseIterable, Identifiable {
        case all
        case first
        case second

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全体"
            case .first: return "前半"
            case .second: return "後半"
            }
        }

        var half: Int? {
            switch self {
            case .all: return nil
            case .first: return 0
            case .second: return 1
            }
        }
    }

    private var playerLookup: [UUID: Player] {
        timelinePresentation.playerLookup
    }

    private var editableEvents: [StatEvent] {
        timelinePresentation.visibleEvents
    }

    private var timelineAutoScrollIdentityBucket: Int {
        guard timelineAutoScrollDirection != 0 else { return 0 }
        return Int((timelineAutoScrollAccumulatedPixels / 12).rounded())
    }

    private var scoringEvents: [StatEvent] {
        timelinePresentation.scoringEvents
    }

    private var scoringProgression: [UUID: (home: Int, away: Int)] {
        timelinePresentation.scoringProgression
    }

    var body: some View {
        ZStack {
            timelineBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if didLoad {
                    editorSurface
                } else {
                    loadingView
                }
            }

        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadDataIfNeeded()
        }
        .onAppear {
            loadMatchClockSettings()
            configureVideoPlayerForCurrentMatch()
        }
        .onChange(of: selectedScope) { _, _ in
            didSetInitialPlayheadPosition = false
            stopTimelinePlayback()
            rebuildTimelinePresentation()
        }
        .onChange(of: timelineScrollOffset) { _, _ in
            guard !isTimelineScrollSyncSuppressed,
                  timelineAutoScrollDirection == 0 else { return }
            syncPlayheadWithScroll()
        }
        .onChange(of: selectedVideoItems) { _, items in
            importSelectedVideos(items)
        }
        .onReceive(NotificationCenter.default.publisher(for: .videoStorageCopyProgress)) { notification in
            updateVideoImportProgress(from: notification)
        }
        .alert("保存できませんでした", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .sheet(item: $selectedEvent) { event in
            EventTimeEditorSheet(
                event: event,
                editorTitle: editorTitle(for: event),
                eventTitle: eventTitle(for: event),
                eventSubtitle: eventSubtitle(for: event),
                halfText: halfLabel(event.half),
                impactText: scoreImpactText(for: event),
                impactColor: scoreImpactColor(for: event),
                accent: categoryColor(for: event),
                onAdjust: { delta in adjust(event, by: delta) },
                onDelete: {
                    requestDeleteTimelineEvent(event)
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isAddEventSheetPresented) {
            TimelineEventAddSheet(
                initialCategory: categoryPendingAddition,
                initialHalf: selectedScope.half ?? 0,
                homeTeamName: teamName(for: match.homeTeamID),
                awayTeamName: teamName(for: match.awayTeamID),
                homePlayers: players(forTeamID: match.homeTeamID),
                awayPlayers: players(forTeamID: match.awayTeamID),
                onAdd: { draft in
                    addTimelineEvent(from: draft)
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isMatchClockSettingsPresented) {
            MatchClockSettingsSheet(
                initialSettings: matchClockSettings,
                currentTimelineSecond: playheadTimelineSecond,
                currentHalf: selectedScope.half,
                secondHalfTimelineOffset: fullTimelineHalfOffset(for: 1),
                onSave: { settings in
                    updateMatchClockSettings(settings)
                }
            )
            .presentationDetents([.large])
        }
        .confirmationDialog("イベントを削除しますか", isPresented: $isDeleteConfirmationPresented) {
            Button("削除", role: .destructive) {
                if let candidate = eventPendingDeletion,
                   let event = events.first(where: { $0.id == candidate.id }) {
                    deleteTimelineEvent(event)
                }
            }
        } message: {
            Text(eventPendingDeletion?.title ?? "")
        }
        .confirmationDialog("動画を削除しますか", isPresented: $isVideoDeleteConfirmationPresented) {
            Button("削除", role: .destructive) {
                deleteSelectedVideoClip()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text(videoDeletionMessage)
        }
        .onDisappear {
            pendingTimelineSaveTask?.cancel()
            videoClipLoadingTask?.cancel()
            pendingScrollSeekTask?.cancel()
            stopTimelinePlayback()
            resetTimelineAutoScroll()
            saveTimelineChanges()
        }
    }

    private var timelineBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.01, green: 0.04, blue: 0.08),
                Color(red: 0.03, green: 0.08, blue: 0.13),
                Color(red: 0.01, green: 0.03, blue: 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var topBar: some View {
        ZStack {
            Text("タイムライン編集")
                .font(.title3.weight(.black))
                .foregroundStyle(.white)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                ShareLink(item: timelineShareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("タイムラインを書き出し")
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private var timelineShareText: String {
        "\(teamName(for: match.homeTeamID)) \(score(for: match.homeTeamID)) - \(score(for: match.awayTeamID)) \(teamName(for: match.awayTeamID)) / \(timeText(playheadTimelineSecond))"
    }

    private var editorSurface: some View {
        GeometryReader { geometry in
            let verticalGap: CGFloat = 9
            let previewHeight = min(max(geometry.size.height * 0.30, 188), 218)
            let controlsHeight: CGFloat = 56
            let hintHeight: CGFloat = 24
            let actionStripHeight: CGFloat = 76
            let calculatedTimelineHeight = max(
                224,
                geometry.size.height
                    - previewHeight
                    - controlsHeight
                    - hintHeight
                    - actionStripHeight
                    - verticalGap * 4
                    - 8
            )
            let timelineHeight = min(
                calculatedTimelineHeight,
                timelineRulerHeight + timelineTrackRowHeight * 7 + 1
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: verticalGap) {
                    videoPreview
                        .frame(height: previewHeight)

                    playbackControls(maxSeconds: timelinePresentation.maxSeconds)
                        .frame(height: controlsHeight)

                    timelineEditorPanel
                        .frame(height: timelineHeight)

                    timelineScrollHint
                        .frame(height: hintHeight)

                    categoryActionStrip
                        .frame(height: actionStripHeight)
                }
                .frame(minHeight: geometry.size.height, alignment: .top)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
            .onAppear {
                updateTimelineAvailableViewportWidth(geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, width in
                updateTimelineAvailableViewportWidth(width)
            }
        }
    }

    private var videoPreview: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let videoPlayer {
                    TimelineVideoPlayerView(player: videoPlayer)
                        .background(Color.black)
                } else {
                    RugbyVideoPreview()
                }
            }

            LinearGradient(
                colors: [.black.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)

            VStack(alignment: .trailing, spacing: 8) {
                if !importedVideoClips.isEmpty {
                    videoStatusBadge
                }

                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedVideoItems, maxSelectionCount: 12, matching: .videos) {
                        Label("動画を追加", systemImage: "video.badge.plus")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(Color.black.opacity(0.46))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isVideoImporting)

                    if !importedVideoClips.isEmpty {
                        Button {
                            videoClipPendingDeletion = selectedVideoClip ?? importedVideoClips.last
                            isVideoDeleteConfirmationPresented = true
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.46))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isVideoImporting)
                    }
                }
            }
            .padding(10)

            if isVideoImporting {
                ZStack {
                    Color.black.opacity(0.56)

                    VStack(spacing: 10) {
                        Text(videoImportTitle)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.white)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                Capsule()
                                    .fill(Color.timelineHome)
                                    .frame(width: max(4, proxy.size.width * CGFloat(videoImportProgress)))
                            }
                        }
                        .frame(height: 8)

                        Text(videoImportDetailText)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(0.52))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.26), radius: 16, x: 0, y: 10)
    }

    private var videoStatusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "film.stack")
                .font(.caption.weight(.black))

            Text(videoStatusText)
                .font(.caption.weight(.black).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.black.opacity(0.48))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private var videoStatusText: String {
        guard let selectedVideoClip,
              let index = importedVideoClips.firstIndex(where: { $0.id == selectedVideoClip.id }) else {
            return "\(importedVideoClips.count)本"
        }
        return "\(index + 1)/\(importedVideoClips.count)  \(timeText(selectedVideoClip.durationSeconds))"
    }

    private func playbackControls(maxSeconds: Int) -> some View {
        ZStack {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Text(timeText(min(playheadTimelineSecond, Double(maxSeconds))))
                        .foregroundStyle(Color.timelineHome)
                    Text("/ \(timeText(maxSeconds))")
                        .foregroundStyle(.white.opacity(0.52))
                }
                .font(.system(size: 18, weight: .bold).monospacedDigit())

                Spacer(minLength: 46)

                HStack(spacing: 10) {
                    timelineRoundControl(systemName: "arrow.uturn.backward") {
                        nudgePlayhead(by: -10, maxSeconds: maxSeconds)
                    }

                    timelineRoundControl(systemName: "arrow.uturn.forward") {
                        nudgePlayhead(by: 10, maxSeconds: maxSeconds)
                    }

                    timelineRoundControl(systemName: "timer") {
                        stopTimelinePlayback()
                        isMatchClockSettingsPresented = true
                    }
                }
            }

            Button {
                toggleTimelinePlayback(maxSeconds: maxSeconds)
            } label: {
                Image(systemName: isTimelinePlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isTimelinePlaying ? "一時停止" : "再生")
        }
    }

    private func timelineRoundControl(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.045))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var timelineEditorPanel: some View {
        let maxSeconds = timelinePresentation.maxSeconds
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)
        let renderedViewportWidth = max(timelineRenderedViewportWidth, 1)
        let renderedOffset = timelineRenderWindow.key.renderOffset >= 0
            ? CGFloat(timelineRenderWindow.key.renderOffset)
            : max(0, timelineRenderOffset)
        let renderedFrame = timelineRenderedFrame(
            renderOffset: renderedOffset,
            viewportWidth: renderedViewportWidth,
            contentWidth: contentWidth
        )
        let rowsHeight = CGFloat(trackDefinitions.count + timelineTimeRowCount) * timelineTrackRowHeight

        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                timelineRulerRow(
                    maxSeconds: maxSeconds,
                    contentWidth: contentWidth,
                    renderedFrame: renderedFrame,
                    renderedViewportWidth: renderedViewportWidth
                )
                .frame(height: timelineRulerHeight)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                ScrollView(.vertical, showsIndicators: false) {
                    timelineTracksRow(
                        maxSeconds: maxSeconds,
                        contentWidth: contentWidth,
                        renderedFrame: renderedFrame,
                        renderedViewportWidth: renderedViewportWidth,
                        rowsHeight: rowsHeight
                    )
                    .frame(height: rowsHeight)
                }
            }

            timelinePlayheadOverlay
        }
        .background(Color(red: 0.01, green: 0.05, blue: 0.09).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func timelineRulerRow(
        maxSeconds: Int,
        contentWidth: CGFloat,
        renderedFrame: (origin: CGFloat, width: CGFloat),
        renderedViewportWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: timelineTrackLabelWidth, height: timelineRulerHeight)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                }

            TimelineNativeScrollViewport(
                contentWidth: contentWidth,
                viewportHeight: timelineRulerHeight,
                renderBucketWidth: timelineRenderBucketWidth,
                hostOrigin: renderedFrame.origin,
                hostWidth: renderedFrame.width,
                contentIdentity: TimelineViewportContentIdentity(
                    kind: "compact-ruler",
                    renderWindowKey: timelineRenderWindow.key
                ),
                scrollOffset: $timelineScrollOffset,
                onViewportFrameChange: { _ in },
                onRenderFrameChange: { renderOffset, viewportWidth in
                    updateTimelineRenderWindow(
                        renderOffset: renderOffset,
                        viewportWidth: viewportWidth,
                        maxSeconds: maxSeconds,
                        contentWidth: contentWidth
                    )
                }
            ) {
                timelineScrollableRuler(
                    ticks: timelineRenderWindow.ticks,
                    maxSeconds: maxSeconds,
                    contentWidth: contentWidth,
                    contentOrigin: renderedFrame.origin,
                    windowWidth: renderedFrame.width
                )
            }
        }
    }

    private func timelineTracksRow(
        maxSeconds: Int,
        contentWidth: CGFloat,
        renderedFrame: (origin: CGFloat, width: CGFloat),
        renderedViewportWidth: CGFloat,
        rowsHeight: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            timelineTrackLabels(rowsHeight: rowsHeight)

            TimelineNativeScrollViewport(
                contentWidth: contentWidth,
                viewportHeight: rowsHeight,
                renderBucketWidth: timelineRenderBucketWidth,
                hostOrigin: renderedFrame.origin,
                hostWidth: renderedFrame.width,
                contentIdentity: TimelineViewportContentIdentity(
                    kind: "compact-tracks",
                    renderWindowKey: timelineRenderWindow.key,
                    selectedEventID: selectedTimelineEventID,
                    autoScrollPixels: timelineAutoScrollIdentityBucket,
                    videoClipIDs: importedVideoClips.map(\.id).joined(separator: "|"),
                    selectedVideoClipID: selectedVideoClipID
                ),
                scrollOffset: $timelineScrollOffset,
                onViewportFrameChange: { frame in
                    if timelineViewportFrame != frame {
                        timelineViewportFrame = frame
                    }
                },
                onRenderFrameChange: { renderOffset, viewportWidth in
                    updateTimelineRenderWindow(
                        renderOffset: renderOffset,
                        viewportWidth: viewportWidth,
                        maxSeconds: maxSeconds,
                        contentWidth: contentWidth
                    )
                }
            ) {
                timelineScrollableTrackRows(
                    maxSeconds: maxSeconds,
                    contentWidth: contentWidth,
                    renderWindow: timelineRenderWindow,
                    contentOrigin: renderedFrame.origin,
                    windowWidth: renderedFrame.width,
                    rowsHeight: rowsHeight
                )
            }
        }
    }

    private func timelineTrackLabels(rowsHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineUtilityTrackLabel(
                title: "VIDEO",
                systemImage: "film.stack",
                color: .timelineVideo
            )

            timelineUtilityTrackLabel(
                title: "MATCH",
                systemImage: "timer",
                color: .timelineMatch
            )

            ForEach(trackDefinitions) { track in
                timelineUtilityTrackLabel(
                    title: trackDisplayTitle(track),
                    systemImage: track.systemImage,
                    color: track.color
                )
            }
        }
        .frame(width: timelineTrackLabelWidth, height: rowsHeight, alignment: .topLeading)
        .background(Color.black.opacity(0.001))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    private func timelineUtilityTrackLabel(
        title: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.black))
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .frame(width: timelineTrackLabelWidth, height: timelineTrackRowHeight, alignment: .leading)
        .padding(.leading, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.055))
                .frame(height: 1)
        }
    }

    private func timelineScrollableTrackRows(
        maxSeconds: Int,
        contentWidth: CGFloat,
        renderWindow: TimelineRenderWindow,
        contentOrigin: CGFloat,
        windowWidth: CGFloat,
        rowsHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            videoTimelineScrollableTrack(
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                viewportWidth: windowWidth,
                contentOrigin: contentOrigin,
                windowWidth: windowWidth
            )

            matchTimelineScrollableTrack(
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                viewportWidth: windowWidth,
                renderOffset: CGFloat(renderWindow.key.renderOffset),
                contentOrigin: contentOrigin,
                windowWidth: windowWidth
            )

            ForEach(trackDefinitions) { track in
                timelineScrollableTrackRow(
                    track,
                    events: renderWindow.trackEvents[track.id, default: []],
                    maxSeconds: maxSeconds,
                    contentWidth: contentWidth,
                    viewportWidth: windowWidth,
                    renderOffset: CGFloat(renderWindow.key.renderOffset),
                    contentOrigin: contentOrigin,
                    windowWidth: windowWidth
                )
            }
        }
        .frame(width: windowWidth, height: rowsHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(timelineZoomGesture)
    }

    private var timelinePlayheadOverlay: some View {
        GeometryReader { proxy in
            let scrollWidth = max(0, proxy.size.width - timelineTrackLabelWidth)
            let x = timelineTrackLabelWidth + scrollWidth / 2

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 1, height: max(0, proxy.size.height - timelineRulerHeight + 15))
                    .offset(x: x, y: timelineRulerHeight - 15)

                Circle()
                    .fill(Color.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.32), radius: 5, y: 2)
                    .offset(x: x - 6.5, y: timelineRulerHeight - 21)
            }
            .allowsHitTesting(false)
        }
    }

    private var timelineScrollHint: some View {
        HStack(spacing: 14) {
            Image(systemName: "chevron.up.chevron.down")
            Text("上下にスクロールして他のトラックを表示")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Image(systemName: "chevron.up.chevron.down")
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.white.opacity(0.48))
        .frame(maxWidth: .infinity)
    }

    private var categoryActionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TimelineEventCategory.allCases) { category in
                    categoryActionTile(category)
                }
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 2)
        }
    }

    private func categoryActionTile(_ category: TimelineEventCategory) -> some View {
        Button {
            categoryPendingAddition = category
            isAddEventSheetPresented = true
        } label: {
            VStack(spacing: 5) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 24, weight: .black))
                    .frame(height: 27)

                Text(category.shortTitle)
                    .font(.subheadline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(width: 64, height: 68)
            .background(
                LinearGradient(
                    colors: [
                        category.color.opacity(0.92),
                        category.color.opacity(0.54)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: category.color.opacity(0.24), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func trackDisplayTitle(_ track: TimelineTrackDefinition) -> String {
        track.title
    }

    private var matchInfoCard: some View {
        HStack(alignment: .center, spacing: 10) {
            teamColumn(teamID: match.homeTeamID, label: "HOME", accent: .blue)

            VStack(spacing: 6) {
                Text("\(score(for: match.homeTeamID)) - \(score(for: match.awayTeamID))")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                HStack(spacing: 8) {
                    scoreChip("前半", half: 0)
                    scoreChip("後半", half: 1)
                }
            }
            .frame(maxWidth: .infinity)

            teamColumn(teamID: match.awayTeamID, label: "AWAY", accent: .red)
        }
        .padding(12)
        .timelineCard()
    }

    private var scopePicker: some View {
        HStack(spacing: 0) {
            ForEach(TimelineScope.allCases) { scope in
                Button {
                    selectedScope = scope
                } label: {
                    Text(scope.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selectedScope == scope ? .white : .white.opacity(0.48))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background {
                            if selectedScope == scope {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.blue.opacity(0.72))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.07))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private var trackSummary: some View {
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("編集トラック", systemImage: "slider.horizontal.3")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    isAddEventSheetPresented = true
                } label: {
                    Label("追加", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.blue.opacity(0.72))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Text("\(timelinePresentation.visibleEvents.count)件")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 8) {
                metricChip("得点", count: timelinePresentation.scoringCount, color: .blue)
                metricChip("セット", count: timelinePresentation.setPieceCount, color: .teal)
                metricChip("区間", count: timelinePresentation.possessionCount, color: .indigo)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(trackDefinitions) { track in
                    trackBadge(track, count: timelinePresentation.trackCounts[track.id, default: 0])
                }
            }
        }
        .padding(12)
        .timelineCard()
    }

    private var horizontalTimeline: some View {
        let maxSeconds = timelinePresentation.maxSeconds
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)
        let renderedViewportWidth = max(timelineRenderedViewportWidth, 1)
        let renderedOffset = timelineRenderWindow.key.renderOffset >= 0
            ? CGFloat(timelineRenderWindow.key.renderOffset)
            : max(0, timelineRenderOffset)
        let renderedFrame = timelineRenderedFrame(
            renderOffset: renderedOffset,
            viewportWidth: renderedViewportWidth,
            contentWidth: contentWidth
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("横タイムライン", systemImage: "timeline.selection")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(zoomText)  目盛\(timeText(timelineTickInterval(maxSeconds: maxSeconds)))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }

            timelineZoomControls

            HStack(spacing: 0) {
                timelineFixedLabels

                TimelineNativeScrollViewport(
                    contentWidth: contentWidth,
                    viewportHeight: timelineViewportHeight,
                    renderBucketWidth: timelineRenderBucketWidth,
                    hostOrigin: renderedFrame.origin,
                    hostWidth: renderedFrame.width,
                    contentIdentity: TimelineViewportContentIdentity(
                        kind: "legacy-full",
                        renderWindowKey: timelineRenderWindow.key,
                        selectedEventID: selectedTimelineEventID,
                        autoScrollPixels: timelineAutoScrollIdentityBucket,
                        videoClipIDs: importedVideoClips.map(\.id).joined(separator: "|"),
                        selectedVideoClipID: selectedVideoClipID
                    ),
                    scrollOffset: $timelineScrollOffset,
                    onViewportFrameChange: { frame in
                        if timelineViewportFrame != frame {
                            timelineViewportFrame = frame
                        }
                    },
                    onRenderFrameChange: { renderOffset, viewportWidth in
                        updateTimelineRenderWindow(
                            renderOffset: renderOffset,
                            viewportWidth: viewportWidth,
                            maxSeconds: maxSeconds,
                            contentWidth: contentWidth
                        )
                    }
                ) {
                    timelineScrollableContent(
                        maxSeconds: maxSeconds,
                        contentWidth: contentWidth,
                        renderWindow: timelineRenderWindow,
                        viewportWidth: renderedViewportWidth,
                        contentOrigin: renderedFrame.origin,
                        windowWidth: renderedFrame.width
                    )
                }
            }
            .frame(height: timelineViewportHeight)
        }
        .padding(12)
        .timelineCard()
    }

    private var timelineViewportHeight: CGFloat {
        timelineRulerHeight + CGFloat(trackDefinitions.count) * timelineTrackRowHeight
    }

    private var timelineFixedLabels: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TRACK")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.44))
                .frame(width: timelineTrackLabelWidth, height: 28, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 18)
                Text("MATCH")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .frame(width: timelineTrackLabelWidth, height: 44, alignment: .leading)

            ForEach(trackDefinitions) { track in
                HStack(spacing: 6) {
                    Image(systemName: track.systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(track.color)
                        .frame(width: 18)
                    Text(track.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: timelineTrackLabelWidth, height: 44, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .frame(width: timelineTrackLabelWidth, height: timelineViewportHeight, alignment: .topLeading)
        .background(Color.black.opacity(0.001))
    }

    private func timelineScrollableContent(
        maxSeconds: Int,
        contentWidth: CGFloat,
        renderWindow: TimelineRenderWindow,
        viewportWidth: CGFloat,
        contentOrigin: CGFloat,
        windowWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineScrollableRuler(
                ticks: renderWindow.ticks,
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                contentOrigin: contentOrigin,
                windowWidth: windowWidth
            )
            matchTimelineScrollableTrack(
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                viewportWidth: viewportWidth,
                renderOffset: CGFloat(renderWindow.key.renderOffset),
                contentOrigin: contentOrigin,
                windowWidth: windowWidth
            )
            ForEach(trackDefinitions) { track in
                timelineScrollableTrackRow(
                    track,
                    events: renderWindow.trackEvents[track.id, default: []],
                    maxSeconds: maxSeconds,
                    contentWidth: contentWidth,
                    viewportWidth: viewportWidth,
                    renderOffset: CGFloat(renderWindow.key.renderOffset),
                    contentOrigin: contentOrigin,
                    windowWidth: windowWidth
                )
            }
        }
        .padding(.vertical, 6)
        .frame(width: windowWidth, height: timelineViewportHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(timelineZoomGesture)
    }

    private func timelineScrollableRuler(
        ticks: [Int],
        maxSeconds: Int,
        contentWidth: CGFloat,
        contentOrigin: CGFloat,
        windowWidth: CGFloat
    ) -> some View {
        let majorTicks = ticks.isEmpty ? visibleTimelineTicks(
            maxSeconds: maxSeconds,
            contentWidth: contentWidth,
            viewportWidth: windowWidth,
            scrollOffset: contentOrigin
        ) : ticks
        let majorSet = Set(majorTicks)
        let minorTicks = visibleTimelineMinorTicks(
            maxSeconds: maxSeconds,
            contentWidth: contentWidth,
            viewportWidth: windowWidth,
            scrollOffset: contentOrigin
        ).filter { !majorSet.contains($0) }

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.055))
                .frame(width: max(34, windowWidth), height: 1)
                .offset(y: timelineRulerHeight - 1)

            timelineNonEditableZones(
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                contentOrigin: contentOrigin,
                windowWidth: windowWidth,
                height: timelineRulerHeight
            )

            ForEach(minorTicks, id: \.self) { second in
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 1, height: 13)
                    .offset(x: xOffset(for: second, maxSeconds: maxSeconds, contentWidth: contentWidth) - contentOrigin, y: 31)
            }

            ForEach(majorTicks, id: \.self) { second in
                VStack(spacing: 6) {
                    Text(timelineRulerText(for: second))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.52))
                    Rectangle()
                        .fill(Color.white.opacity(0.24))
                        .frame(width: 1, height: 17)
                }
                .offset(x: xOffset(for: second, maxSeconds: maxSeconds, contentWidth: contentWidth) - contentOrigin)
            }

            if selectedScope == .all {
                halfDivider(maxSeconds: maxSeconds, contentWidth: contentWidth, scrollOffset: contentOrigin)
                Text("後半 00:00")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.blue)
                    .offset(x: xOffset(for: halfTimelineOffset(for: 1), maxSeconds: maxSeconds, contentWidth: contentWidth) - contentOrigin + 4, y: 0)
            }
        }
        .frame(width: windowWidth, height: timelineRulerHeight, alignment: .topLeading)
        .clipped()
    }

    private func videoTimelineScrollableTrack(
        maxSeconds: Int,
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        contentOrigin: CGFloat,
        windowWidth: CGFloat
    ) -> some View {
        let visibleClips = videoClipsForTimelineScope(maxSeconds: maxSeconds)

        return ZStack(alignment: .leading) {
            visibleTrackBackground(
                windowWidth: windowWidth,
                opacity: 0.075
            )

            timelineNonEditableZones(
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                contentOrigin: contentOrigin,
                windowWidth: windowWidth,
                height: timelineTrackRowHeight
            )

            if visibleClips.isEmpty {
                Text("動画なし")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .offset(x: max(8, xOffset(for: 0, maxSeconds: maxSeconds, contentWidth: contentWidth) - contentOrigin))
            } else {
                ForEach(visibleClips) { clip in
                    videoTimelineClipBlock(
                        clip,
                        maxSeconds: maxSeconds,
                        contentWidth: contentWidth,
                        contentOrigin: contentOrigin,
                        windowWidth: windowWidth
                    )
                }
            }
        }
        .frame(width: windowWidth, height: timelineTrackRowHeight, alignment: .leading)
        .clipped()
    }

    private func videoTimelineClipBlock(
        _ clip: TimelineVideoClip,
        maxSeconds: Int,
        contentWidth: CGFloat,
        contentOrigin: CGFloat,
        windowWidth: CGFloat
    ) -> some View {
        let scopeStartSecond = timelineScopeVideoStartSecond()
        let timelineStart = max(0, clip.startSeconds - scopeStartSecond)
        let timelineEnd = min(Double(maxSeconds), clip.endSeconds - scopeStartSecond)
        let rawX = xOffset(for: timelineStart, maxSeconds: maxSeconds, contentWidth: contentWidth)
        let rawEndX = xOffset(for: timelineEnd, maxSeconds: maxSeconds, contentWidth: contentWidth)
        let visibleLeft = max(0, contentOrigin)
        let visibleRight = min(contentWidth, contentOrigin + windowWidth)
        let renderedX = max(rawX, visibleLeft)
        let renderedEndX = min(rawEndX, visibleRight)
        let renderedWidth = max(22, renderedEndX - renderedX)
        let isSelected = selectedVideoClipID == clip.id

        return Group {
            if timelineEnd > 0 && timelineStart < Double(maxSeconds) && rawEndX >= visibleLeft && rawX <= visibleRight {
                Button {
                    stopTimelinePlayback()
                    selectedVideoClipID = clip.id
                    scrollToTimelineSecond(timelineStart, maxSeconds: maxSeconds)
                } label: {
                    HStack(spacing: 6) {
                        Text(videoClipTitle(for: clip, width: renderedWidth))
                            .font(.caption.weight(.black).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .padding(.horizontal, 8)
                    .frame(width: renderedWidth, height: 28, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.timelineVideo.opacity(0.92),
                                Color.timelineVideo.opacity(0.50)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.18), lineWidth: isSelected ? 1.6 : 1)
                    )
                    .offset(x: renderedX - contentOrigin)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func videoClipTitle(for clip: TimelineVideoClip, width: CGFloat) -> String {
        let prefix = "V\(clip.index + 1)"
        if width > 120 {
            return "\(prefix) 00:00-\(timeText(clip.durationSeconds))"
        }
        if width > 72 {
            return "\(prefix) \(timeText(clip.durationSeconds))"
        }
        return prefix
    }

    private func matchTimelineScrollableTrack(
        maxSeconds: Int,
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        renderOffset: CGFloat,
        contentOrigin: CGFloat,
        windowWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            visibleTrackBackground(
                windowWidth: windowWidth,
                opacity: 0.07
            )
            .onTapGesture {
                selectedTimelineEventID = nil
            }

            matchHalfBand(
                half: selectedScope.half ?? 0,
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                viewportWidth: windowWidth,
                scrollOffset: contentOrigin,
                positionOffset: contentOrigin
            )

            if selectedScope == .all {
                matchHalfBand(
                    half: 1,
                    maxSeconds: maxSeconds,
                    contentWidth: contentWidth,
                    viewportWidth: windowWidth,
                    scrollOffset: contentOrigin,
                    positionOffset: contentOrigin
                )
                halfDivider(
                    maxSeconds: maxSeconds,
                    contentWidth: contentWidth,
                    scrollOffset: contentOrigin,
                    height: timelineTrackRowHeight
                )
                halfChangeLabel(maxSeconds: maxSeconds, contentWidth: contentWidth, scrollOffset: contentOrigin)
            }

            matchClockStoppagesLayer(
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                contentOrigin: contentOrigin,
                windowWidth: windowWidth
            )
        }
        .frame(width: windowWidth, height: timelineTrackRowHeight, alignment: .leading)
        .clipped()
    }

    private func matchClockStoppagesLayer(
        maxSeconds: Int,
        contentWidth: CGFloat,
        contentOrigin: CGFloat,
        windowWidth: CGFloat
    ) -> some View {
        let visibleStoppages = matchClockSettings.stoppagesForTimelineScope(selectedScope.half)

        return ZStack(alignment: .leading) {
            ForEach(visibleStoppages) { stoppage in
                matchClockStoppageBlock(
                    stoppage,
                    maxSeconds: maxSeconds,
                    contentWidth: contentWidth,
                    contentOrigin: contentOrigin,
                    windowWidth: windowWidth
                )
            }
        }
        .frame(width: windowWidth, height: timelineTrackRowHeight, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func matchClockStoppageBlock(
        _ stoppage: TimelineMatchClockStop,
        maxSeconds: Int,
        contentWidth: CGFloat,
        contentOrigin: CGFloat,
        windowWidth: CGFloat
    ) -> some View {
        let halfOffset = selectedScope == .all ? halfTimelineOffset(for: stoppage.half) : 0
        let startSecond = halfOffset + matchClockSettings.timelineSecond(
            forClockSecond: stoppage.clockSecond,
            half: stoppage.half
        )
        let endSecond = min(maxSeconds, startSecond + stoppage.durationSeconds)
        let rawX = xOffset(for: startSecond, maxSeconds: maxSeconds, contentWidth: contentWidth)
        let rawEndX = xOffset(for: endSecond, maxSeconds: maxSeconds, contentWidth: contentWidth)
        let visibleLeft = max(0, contentOrigin)
        let visibleRight = min(contentWidth, contentOrigin + windowWidth)
        let renderedX = max(rawX, visibleLeft)
        let renderedEndX = min(rawEndX, visibleRight)
        let renderedWidth = max(18, renderedEndX - renderedX)

        return Group {
            if endSecond > 0 && startSecond < maxSeconds && rawEndX >= visibleLeft && rawX <= visibleRight {
                Text(matchClockStoppageTitle(stoppage, width: renderedWidth))
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .padding(.horizontal, 6)
                    .frame(width: renderedWidth, height: 24, alignment: .leading)
                    .background(Color.orange.opacity(0.84))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.white.opacity(0.26), lineWidth: 1)
                    )
                    .offset(x: renderedX - contentOrigin, y: 9)
            }
        }
    }

    private func matchClockStoppageTitle(_ stoppage: TimelineMatchClockStop, width: CGFloat) -> String {
        if width > 132 {
            return "停止 \(timeText(stoppage.clockSecond)) +\(timeText(stoppage.durationSeconds))"
        }
        if width > 74 {
            return "+\(timeText(stoppage.durationSeconds))"
        }
        return "停止"
    }

    private func timelineScrollableTrackRow(
        _ track: TimelineTrackDefinition,
        events: [TimelineRenderEvent],
        maxSeconds: Int,
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        renderOffset: CGFloat,
        contentOrigin: CGFloat,
        windowWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            visibleTrackBackground(
                windowWidth: windowWidth,
                opacity: 0.055
            )
            .onTapGesture {
                selectedTimelineEventID = nil
            }

            timelineNonEditableZones(
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                contentOrigin: contentOrigin,
                windowWidth: windowWidth,
                height: timelineTrackRowHeight
            )

            if selectedScope == .all {
                halfDivider(maxSeconds: maxSeconds, contentWidth: contentWidth, scrollOffset: contentOrigin)
            }

            TimelineEventBlocksLayer(
                events: events,
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                viewportWidth: windowWidth,
                renderOffset: contentOrigin,
                positionOffset: contentOrigin,
                editableStartX: xOffset(for: 0, maxSeconds: maxSeconds, contentWidth: contentWidth),
                editableEndX: xOffset(for: maxSeconds, maxSeconds: maxSeconds, contentWidth: contentWidth),
                color: track.color,
                selectedEventID: selectedTimelineEventID,
                resizeSensitivity: resizeSensitivity,
                resizeAutoScrollTranslation: timelineAutoScrollAccumulatedPixels,
                onTap: { item in
                    if selectedTimelineEventID == item.id {
                        selectedEvent = item.event
                    } else {
                        selectedTimelineEventID = item.id
                        scrollToTimelineSecond(item.startSeconds, maxSeconds: maxSeconds)
                    }
                },
                onDragChanged: { _, translation, location in
                    handleTimelineMoveDrag(
                        translation: translation,
                        location: location,
                        maxSeconds: maxSeconds
                    )
                },
                onDragEnded: { item, translation in
                    let movePixels = translation + timelineAutoScrollAccumulatedPixels
                    defer { resetTimelineAutoScroll() }
                    let secondsDelta = Int((movePixels / timelinePointsPerSecond(maxSeconds: maxSeconds, contentWidth: contentWidth)).rounded())
                    guard secondsDelta != 0 else { return }
                    let updatedSecond = clampedTimelineSecond(for: item.event, proposedSecond: item.startSeconds + secondsDelta)
                    updateTimelineEvent(item.event, toTimelineSecond: updatedSecond)
                },
                onDragCancelled: {
                    resetTimelineAutoScroll()
                },
                onResizeStartEnded: { item, translation in
                    defer { resetTimelineAutoScroll() }
                    let resizePixels = resizeTranslation(translation) + timelineAutoScrollAccumulatedPixels
                    let secondsDelta = Int((resizePixels / timelinePointsPerSecond(maxSeconds: maxSeconds, contentWidth: contentWidth)).rounded())
                    guard secondsDelta != 0 else { return }
                    updateTimelineIntervalEvent(
                        item.event,
                        proposedStartTimelineSecond: item.startSeconds + secondsDelta,
                        proposedEndTimelineSecond: item.startSeconds + item.durationSeconds
                    )
                },
                onResizeEndEnded: { item, translation in
                    defer { resetTimelineAutoScroll() }
                    let resizePixels = resizeTranslation(translation) + timelineAutoScrollAccumulatedPixels
                    let secondsDelta = Int((resizePixels / timelinePointsPerSecond(maxSeconds: maxSeconds, contentWidth: contentWidth)).rounded())
                    guard secondsDelta != 0 else { return }
                    updateTimelineIntervalEvent(
                        item.event,
                        proposedStartTimelineSecond: item.startSeconds,
                        proposedEndTimelineSecond: item.startSeconds + item.durationSeconds + secondsDelta
                    )
                },
                onResizeDragChanged: { edge, translation, location in
                    handleTimelineResizeDrag(
                        edge: edge,
                        translation: translation,
                        location: location,
                        maxSeconds: maxSeconds
                    )
                },
                onResizeDragEnded: {
                    resetTimelineAutoScroll()
                }
            )
            .equatable()

            timelineNonEditableZones(
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                contentOrigin: contentOrigin,
                windowWidth: windowWidth,
                height: timelineTrackRowHeight
            )
        }
        .frame(width: windowWidth, height: timelineTrackRowHeight, alignment: .leading)
        .clipped()
    }

    private func visibleTrackBackground(
        windowWidth: CGFloat,
        opacity: Double
    ) -> some View {
        Rectangle()
            .fill(Color.white.opacity(opacity))
            .frame(width: max(34, windowWidth), height: timelineTrackRowHeight)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.055))
                    .frame(height: 1)
            }
    }

    private func timelineNonEditableZones(
        maxSeconds: Int,
        contentWidth: CGFloat,
        contentOrigin: CGFloat,
        windowWidth: CGFloat,
        height: CGFloat
    ) -> some View {
        let editStartX = xOffset(for: 0, maxSeconds: maxSeconds, contentWidth: contentWidth) - contentOrigin
        let editEndX = xOffset(for: maxSeconds, maxSeconds: maxSeconds, contentWidth: contentWidth) - contentOrigin
        let leftWidth = max(0, min(editStartX, windowWidth))
        let rightX = max(0, min(editEndX, windowWidth))
        let rightWidth = max(0, windowWidth - rightX)

        return ZStack(alignment: .topLeading) {
            nonEditableTimelineZone(width: leftWidth, height: height)
                .opacity(leftWidth > 0 ? 1 : 0)

            nonEditableTimelineZone(width: rightWidth, height: height)
                .offset(x: rightX)
                .opacity(rightWidth > 0 ? 1 : 0)

            timelineEditBoundaryLine(height: height)
                .offset(x: editStartX)
                .opacity(editStartX >= 0 && editStartX <= windowWidth ? 1 : 0)

            timelineEditBoundaryLine(height: height)
                .offset(x: editEndX)
                .opacity(editEndX >= 0 && editEndX <= windowWidth ? 1 : 0)
        }
        .frame(width: windowWidth, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func nonEditableTimelineZone(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.36))
            TimelineDisabledPattern()
                .opacity(0.9)
            Rectangle()
                .fill(Color(red: 0.01, green: 0.04, blue: 0.07).opacity(0.42))
        }
        .frame(width: max(0, width), height: height)
    }

    private func timelineEditBoundaryLine(height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.44))
            .frame(width: 1.5, height: height)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.timelineHome.opacity(0.42))
                    .frame(width: 3, height: height)
                    .offset(x: -1.5)
            }
    }

    private func clampedTimelineScrollOffset(_ offset: CGFloat, contentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        min(max(0, offset), max(0, contentWidth - viewportWidth))
    }

    private func timelineRenderedFrame(
        renderOffset: CGFloat,
        viewportWidth: CGFloat,
        contentWidth: CGFloat
    ) -> (origin: CGFloat, width: CGFloat) {
        let viewportWidth = max(1, viewportWidth)
        let maxOrigin = max(0, contentWidth - viewportWidth)
        let origin = min(max(0, renderOffset - timelineRenderPadding), maxOrigin)
        let end = min(contentWidth, max(origin + viewportWidth, renderOffset + viewportWidth + timelineRenderPadding))
        return (origin, max(1, end - origin))
    }

    private var timelineZoomControls: some View {
        HStack(spacing: 8) {
            zoomButton(systemName: "minus.magnifyingglass") {
                setTimelineZoom(timelineZoom / 1.35)
            }

            zoomPresetButton("全体") {
                setTimelineZoom(minimumTimelineZoom)
            }

            zoomPresetButton("標準") {
                setTimelineZoom(1.0)
            }

            zoomPresetButton("詳細") {
                setTimelineZoom(6.0)
            }

            zoomButton(systemName: "plus.magnifyingglass") {
                setTimelineZoom(timelineZoom * 1.35)
            }
        }
    }

    private func zoomPresetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func zoomButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 38, height: 34)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var eventListToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isEventListExpanded.toggle()
            }
        } label: {
            HStack {
                Label("イベント一覧", systemImage: isEventListExpanded ? "chevron.up" : "chevron.down")
                    .font(.headline.weight(.black))
                Spacer()
                Text("\(editableEvents.count)件")
                    .font(.caption.weight(.bold).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.white.opacity(0.075))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var eventList: some View {
        let visibleEvents = editableEvents
        let progression = scoringProgression
        let lookup = playerLookup

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("イベント一覧")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Spacer()
                Text("時間順")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if visibleEvents.isEmpty {
                Text("表示できる記録イベントがありません")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.56))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(visibleEvents) { event in
                        eventRow(
                            event,
                            progression: progression[event.id],
                            playerLookup: lookup
                        )
                    }
                }
            }
        }
        .padding(12)
        .timelineCard()
    }

    private func matchHalfBand(
        half: Int,
        maxSeconds: Int,
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        scrollOffset: CGFloat,
        positionOffset: CGFloat = 0
    ) -> some View {
        let offset = selectedScope == .all ? halfTimelineOffset(for: half) : 0
        let duration = timelinePresentation.halfDuration(for: half)
        let rawX = xOffset(for: offset, maxSeconds: maxSeconds, contentWidth: contentWidth)
        let rawEndX = xOffset(for: offset + duration, maxSeconds: maxSeconds, contentWidth: contentWidth)
        let renderPadding: CGFloat = 0
        let visibleLeft = max(0, scrollOffset - renderPadding)
        let visibleRight = min(contentWidth, scrollOffset + viewportWidth + renderPadding)
        let renderedX = max(rawX, visibleLeft)
        let renderedEndX = min(rawEndX, visibleRight)
        let renderedWidth = max(18, renderedEndX - renderedX)
        let label = half == 0 ? "前半" : "後半"
        let stoppageSeconds = matchClockSettings.totalStoppageSeconds(for: half)

        return Group {
            if rawEndX >= visibleLeft && rawX <= visibleRight {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.caption2.weight(.black))
                    Text(timeText(matchClockSettings.clockDuration(for: half)))
                        .font(.caption2.weight(.bold).monospacedDigit())
                    if stoppageSeconds > 0 && renderedWidth > 116 {
                        Text("+\(timeText(stoppageSeconds))")
                            .font(.caption2.weight(.black).monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 8)
                .frame(width: renderedWidth, height: 28, alignment: .leading)
                .background((half == 0 ? Color.white : Color.blue).opacity(half == 0 ? 0.14 : 0.24))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .offset(x: renderedX - positionOffset)
            }
        }
    }

    private func updateTimelineRenderWindow(
        renderOffset: CGFloat,
        viewportWidth: CGFloat,
        maxSeconds: Int,
        contentWidth: CGFloat
    ) {
        timelineRenderOffset = renderOffset
        timelineRenderedViewportWidth = viewportWidth

        let key = TimelineRenderWindowKey(
            presentationVersion: timelinePresentationVersion,
            renderOffset: Int(renderOffset.rounded()),
            viewportWidth: Int(viewportWidth.rounded()),
            contentWidth: Int(contentWidth.rounded()),
            maxSeconds: maxSeconds
        )
        guard timelineRenderWindow.key != key else { return }

        timelineRenderWindow = makeTimelineRenderWindow(
            key: key,
            renderOffset: renderOffset,
            viewportWidth: viewportWidth,
            maxSeconds: maxSeconds,
            contentWidth: contentWidth,
            presentation: timelinePresentation
        )
        positionInitialPlayheadIfNeeded(maxSeconds: maxSeconds, contentWidth: contentWidth)
    }

    private func refreshTimelineRenderWindow(for presentation: TimelinePresentationState, version: Int) {
        guard timelineRenderedViewportWidth > 0 else {
            timelineRenderWindow = .empty
            return
        }

        let maxSeconds = presentation.maxSeconds
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)
        let renderOffset = min(max(0, timelineRenderOffset), max(0, contentWidth - timelineRenderedViewportWidth))
        let key = TimelineRenderWindowKey(
            presentationVersion: version,
            renderOffset: Int(renderOffset.rounded()),
            viewportWidth: Int(timelineRenderedViewportWidth.rounded()),
            contentWidth: Int(contentWidth.rounded()),
            maxSeconds: maxSeconds
        )
        timelineRenderOffset = renderOffset
        timelineRenderWindow = makeTimelineRenderWindow(
            key: key,
            renderOffset: renderOffset,
            viewportWidth: timelineRenderedViewportWidth,
            maxSeconds: maxSeconds,
            contentWidth: contentWidth,
            presentation: presentation
        )
        positionInitialPlayheadIfNeeded(maxSeconds: maxSeconds, contentWidth: contentWidth)
    }

    private func makeTimelineRenderWindow(
        key: TimelineRenderWindowKey,
        renderOffset: CGFloat,
        viewportWidth: CGFloat,
        maxSeconds: Int,
        contentWidth: CGFloat,
        presentation: TimelinePresentationState
    ) -> TimelineRenderWindow {
        let ticks = visibleTimelineTicks(
            maxSeconds: maxSeconds,
            contentWidth: contentWidth,
            viewportWidth: viewportWidth,
            scrollOffset: renderOffset
        )
        var trackEvents: [String: [TimelineRenderEvent]] = [:]
        for track in trackDefinitions {
            trackEvents[track.id] = visibleTrackRenderEvents(
                from: presentation.trackRenderEvents[track.id, default: []],
                maxSeconds: maxSeconds,
                contentWidth: contentWidth,
                viewportWidth: viewportWidth,
                scrollOffset: renderOffset
            )
        }

        return TimelineRenderWindow(
            key: key,
            ticks: ticks,
            trackEvents: trackEvents
        )
    }

    private func visibleTrackRenderEvents(
        from trackEvents: [TimelineRenderEvent],
        maxSeconds: Int,
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        scrollOffset: CGFloat
    ) -> [TimelineRenderEvent] {
        guard viewportWidth > 0 else {
            return []
        }

        let pointsPerSecond = max(timelinePointsPerSecond(maxSeconds: maxSeconds, contentWidth: contentWidth), 0.1)
        let bufferPixels = timelineRenderPadding + timelineRenderBucketWidth
        let bufferSeconds = max(60, Int((bufferPixels / pointsPerSecond).rounded(.up)))
        let trackViewportWidth = viewportWidth
        let visibleStart = Int(
            timelineSecond(forContentX: scrollOffset, maxSeconds: maxSeconds, contentWidth: contentWidth)
                .rounded(.down)
        ) - bufferSeconds
        let visibleEnd = Int(
            timelineSecond(forContentX: scrollOffset + trackViewportWidth, maxSeconds: maxSeconds, contentWidth: contentWidth)
                .rounded(.up)
        ) + bufferSeconds

        var visibleEvents = Array(trackEvents.lazy.filter { event in
            event.endSeconds >= visibleStart && event.startSeconds <= visibleEnd
        }.prefix(96))

        if let selectedTimelineEventID,
           !visibleEvents.contains(where: { $0.id == selectedTimelineEventID }),
           let selectedEvent = trackEvents.first(where: { $0.id == selectedTimelineEventID }) {
            visibleEvents.append(selectedEvent)
        }

        return visibleEvents
    }

    private func updateTimelineEvent(_ event: StatEvent, toTimelineSecond timelineSecond: Int) {
        if event.category == "possession" {
            event.startSeconds = timelineLocalSeconds(from: timelineSecond, half: event.half)
        } else {
            event.seconds = timelineLocalSeconds(from: timelineSecond, half: event.half)
        }

        saveErrorMessage = nil
        rebuildTimelinePresentation()
        scheduleTimelineSave()
    }

    private func updateTimelineIntervalEvent(
        _ event: StatEvent,
        proposedStartTimelineSecond: Int,
        proposedEndTimelineSecond: Int
    ) {
        guard event.category == "possession" else { return }

        if event.startSeconds == nil {
            event.startSeconds = timelineLocalSeconds(from: timelineStartSeconds(for: event), half: event.half)
        }
        let halfStart = halfTimelineOffset(for: event.half)
        let halfEnd = halfStart + timelinePresentation.halfDuration(for: event.half)
        let start = min(max(halfStart, proposedStartTimelineSecond), max(halfStart, halfEnd - 1))
        let end = min(max(start + 1, proposedEndTimelineSecond), halfEnd)
        let startClockSecond = timelineLocalSeconds(from: start, half: event.half)
        let endClockSecond = timelineLocalSeconds(from: end, half: event.half)

        event.startSeconds = startClockSecond
        event.seconds = max(1, endClockSecond - startClockSecond)

        saveErrorMessage = nil
        rebuildTimelinePresentation()
        scheduleTimelineSave()
    }

    private func addTimelineEvent(from draft: TimelineEventDraft) {
        let event = makeStatEvent(from: draft)
        modelContext.insert(event)
        events.append(event)

        do {
            try modelContext.save()
            saveErrorMessage = nil
            selectedTimelineEventID = event.id
            if let scopedHalf = selectedScope.half, scopedHalf != event.half {
                selectedScope = event.half == 0 ? .first : .second
            } else {
                rebuildTimelinePresentation()
            }
        } catch {
            modelContext.delete(event)
            events.removeAll { $0.id == event.id }
            rebuildTimelinePresentation()
            saveErrorMessage = "イベントを追加できませんでした。もう一度試してください。"
        }
    }

    private func deleteTimelineEvent(_ event: StatEvent) {
        pendingTimelineSaveTask?.cancel()
        selectedEvent = nil
        isDeleteConfirmationPresented = false
        eventPendingDeletion = nil
        if selectedTimelineEventID == event.id {
            selectedTimelineEventID = nil
        }

        modelContext.delete(event)
        events.removeAll { $0.id == event.id }

        do {
            try modelContext.save()
            saveErrorMessage = nil
            rebuildTimelinePresentation()
        } catch {
            reloadData()
            saveErrorMessage = "イベントを削除できませんでした。もう一度試してください。"
        }
    }

    private func requestDeleteTimelineEvent(_ event: StatEvent) {
        eventPendingDeletion = TimelineDeletionCandidate(
            id: event.id,
            title: eventTitle(for: event)
        )
        isDeleteConfirmationPresented = true
    }

    private func makeStatEvent(from draft: TimelineEventDraft) -> StatEvent {
        let teamID: UUID?
        switch draft.category {
        case .homePossession:
            teamID = match.homeTeamID
        case .awayPossession:
            teamID = match.awayTeamID
        case .bip:
            teamID = nil
        default:
            teamID = draft.teamSide == .home ? match.homeTeamID : match.awayTeamID
        }

        let outcome: String
        switch draft.category {
        case .homePossession, .awayPossession:
            outcome = "own"
        case .bip:
            outcome = "none"
        case .tryScore:
            outcome = "success"
        default:
            outcome = draft.isSuccessful ? "success" : "fail"
        }

        return StatEvent(
            matchID: match.id,
            teamID: teamID,
            playerID: draft.category.allowsPlayerSelection ? draft.playerID : nil,
            category: draft.category.storageCategory,
            outcome: outcome,
            seconds: draft.category.isDuration ? max(1, draft.durationSeconds) : max(0, draft.seconds),
            startSeconds: draft.category.isDuration ? max(0, draft.seconds) : nil,
            half: draft.half
        )
    }

    private func resizeTranslation(_ translation: CGFloat) -> CGFloat {
        translation * resizeSensitivity
    }

    private func handleTimelineMoveDrag(
        translation: CGFloat,
        location: CGPoint,
        maxSeconds: Int
    ) {
        guard timelineViewportFrame.width > 0 else { return }

        let rightLimit = timelineViewportFrame.maxX - timelineAutoScrollEdgeInset
        let leftLimit = timelineViewportFrame.minX + timelineAutoScrollEdgeInset
        let rightOverflow = max(0, location.x - rightLimit)
        let leftOverflow = max(0, leftLimit - location.x)
        let dragDirection = translation < -8 ? -1 : (translation > 8 ? 1 : 0)
        let pullOverflow = max(0, abs(translation) - 84)

        let direction: Int
        let overflow: CGFloat
        if dragDirection < 0 {
            direction = -1
            overflow = max(leftOverflow, pullOverflow)
        } else if dragDirection > 0 {
            direction = 1
            overflow = max(rightOverflow, pullOverflow)
        } else if leftOverflow > 0 {
            direction = -1
            overflow = leftOverflow
        } else if rightOverflow > 0 {
            direction = 1
            overflow = rightOverflow
        } else {
            stopTimelineAutoScroll()
            return
        }

        guard overflow > 0 else {
            stopTimelineAutoScroll()
            return
        }

        let normalizedOverflow = timelineAutoScrollPower(for: overflow)
        startTimelineAutoScroll(
            direction: direction,
            maxSeconds: maxSeconds,
            intensity: normalizedOverflow
        )
    }

    private func handleTimelineResizeDrag(
        edge: TimelineResizeEdge,
        translation: CGFloat,
        location: CGPoint,
        maxSeconds: Int
    ) {
        guard timelineViewportFrame.width > 0 else { return }

        let direction: Int
        switch edge {
        case .start:
            direction = -1
        case .end:
            direction = 1
        }

        let edgeLimit = direction > 0
            ? timelineViewportFrame.maxX - timelineAutoScrollEdgeInset
            : timelineViewportFrame.minX + timelineAutoScrollEdgeInset
        let edgeOverflow = direction > 0
            ? location.x - edgeLimit
            : edgeLimit - location.x
        let pullOverflow = max(0, abs(resizeTranslation(translation)) - 96)
        let overflow = max(edgeOverflow, pullOverflow)

        guard overflow > 0 else {
            stopTimelineAutoScroll()
            return
        }

        let normalizedOverflow = timelineAutoScrollPower(for: overflow)
        startTimelineAutoScroll(
            direction: direction,
            maxSeconds: maxSeconds,
            intensity: normalizedOverflow
        )
    }

    private func timelineAutoScrollPower(for overflow: CGFloat) -> CGFloat {
        let normalized = min(1.0, max(0, overflow) / (timelineAutoScrollEdgeInset * 1.45))
        return normalized * normalized * (3 - 2 * normalized)
    }

    private func timelineAutoScrollRepeatingStep(for power: CGFloat) -> CGFloat {
        timelineAutoScrollStep * (0.08 + power * 2.45)
    }

    private func startTimelineAutoScroll(direction: Int, maxSeconds: Int, intensity: CGFloat) {
        let normalizedIntensity = (min(1, max(0, intensity)) * 10).rounded() / 10
        let shouldUpdateState = timelineAutoScrollDirection != direction
            || timelineAutoScrollMaxSeconds != maxSeconds
            || abs(timelineAutoScrollIntensity - normalizedIntensity) > 0.001

        if shouldUpdateState {
            timelineAutoScrollDirection = direction
            timelineAutoScrollMaxSeconds = maxSeconds
            timelineAutoScrollIntensity = normalizedIntensity
        }

        guard timelineAutoScrollTask == nil else { return }

        timelineAutoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                guard timelineAutoScrollDirection != 0 else { break }
                let step = timelineAutoScrollRepeatingStep(for: timelineAutoScrollIntensity)
                advanceTimelineAutoScroll(
                    direction: timelineAutoScrollDirection,
                    maxSeconds: timelineAutoScrollMaxSeconds,
                    step: step
                )
                try? await Task.sleep(for: .milliseconds(85))
            }
            timelineAutoScrollTask = nil
        }
    }

    private func advanceTimelineAutoScroll(direction: Int, maxSeconds: Int, step: CGFloat) {
        guard direction != 0 else { return }
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)
        let previousOffset = timelineScrollOffset
        timelineScrollOffset = clampedTimelineScrollOffset(
            timelineScrollOffset + CGFloat(direction) * step,
            contentWidth: contentWidth,
            viewportWidth: timelineViewportFrame.width
        )

        let pixelDelta = timelineScrollOffset - previousOffset
        if pixelDelta != 0 {
            timelineAutoScrollAccumulatedPixels += pixelDelta
        }
    }

    private func stopTimelineAutoScroll() {
        guard timelineAutoScrollDirection != 0
                || timelineAutoScrollIntensity != 0
                || timelineAutoScrollTask != nil else {
            return
        }
        timelineAutoScrollDirection = 0
        timelineAutoScrollIntensity = 0
        timelineAutoScrollTask?.cancel()
        timelineAutoScrollTask = nil
    }

    private func resetTimelineAutoScroll() {
        stopTimelineAutoScroll()
        timelineAutoScrollAccumulatedPixels = 0
    }

    private func scheduleTimelineSave() {
        pendingTimelineSaveTask?.cancel()
        pendingTimelineSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveTimelineChanges()
            }
        }
    }

    private func saveTimelineChanges() {
        do {
            try modelContext.save()
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "変更を保存できませんでした。もう一度試してください。"
        }
    }

    private func toggleTimelinePlayback(maxSeconds: Int) {
        if isTimelinePlaying {
            stopTimelinePlayback()
        } else {
            startTimelinePlayback(maxSeconds: maxSeconds)
        }
    }

    private func startTimelinePlayback(maxSeconds: Int) {
        timelinePlaybackTask?.cancel()
        isTimelinePlaying = true
        let playbackStartSecond = min(playheadTimelineSecond, Double(maxSeconds))
        let playbackStartDate = Date()
        seekVideo(to: playbackStartSecond)
        videoPlayer?.play()
        timelinePlaybackTask = Task { @MainActor in
            while !Task.isCancelled {
                let currentMaxSeconds = timelinePresentation.maxSeconds
                let elapsedSeconds = Date().timeIntervalSince(playbackStartDate)
                let currentSecond = min(playbackStartSecond + elapsedSeconds, Double(currentMaxSeconds))
                scrollToTimelineSecond(currentSecond, maxSeconds: currentMaxSeconds, seekVideo: false)
                syncVideoClipDuringPlayback(at: currentSecond)

                guard currentSecond < Double(currentMaxSeconds) else {
                    stopTimelinePlayback()
                    break
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopTimelinePlayback() {
        timelinePlaybackTask?.cancel()
        timelinePlaybackTask = nil
        pendingScrollSeekTask?.cancel()
        isTimelinePlaying = false
        videoPlayer?.pause()
    }

    private var videoImportTitle: String {
        let countText = videoImportTotalCount > 1 ? " \(videoImportCurrentIndex)/\(videoImportTotalCount)" : ""
        let progressText = videoImportTotalBytes > 0 ? " \(Int((videoImportProgress * 100).rounded()))%" : ""
        return "動画を読み込み中\(countText)\(progressText)"
    }

    private var videoImportDetailText: String {
        guard videoImportTotalBytes > 0 else {
            return "ファイルを確認しています"
        }

        let copiedText = byteCountText(videoImportCopiedBytes)
        let totalText = byteCountText(videoImportTotalBytes)
        if let remainingText = videoImportRemainingText {
            return "\(copiedText) / \(totalText)  残り約 \(remainingText)"
        }
        return "\(copiedText) / \(totalText)"
    }

    private var videoImportRemainingText: String? {
        guard let startedAt = videoImportStartedAt,
              videoImportCopiedBytes > 0,
              videoImportTotalBytes > videoImportCopiedBytes else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0.4 else { return nil }

        let bytesPerSecond = Double(videoImportCopiedBytes) / elapsed
        guard bytesPerSecond > 0 else { return nil }

        let remainingSeconds = Double(videoImportTotalBytes - videoImportCopiedBytes) / bytesPerSecond
        return shortDurationText(remainingSeconds)
    }

    private func resetVideoImportProgress() {
        videoImportProgress = 0
        videoImportCopiedBytes = 0
        videoImportTotalBytes = 0
        videoImportStartedAt = nil
        videoImportCurrentIndex = 0
        videoImportTotalCount = 0
    }

    private func updateVideoImportProgress(from notification: Notification) {
        guard isVideoImporting else { return }
        guard let fraction = notification.userInfo?["fraction"] as? Double,
              let copiedBytes = notification.userInfo?["copiedBytes"] as? Int64,
              let totalBytes = notification.userInfo?["totalBytes"] as? Int64 else {
            return
        }

        if videoImportStartedAt == nil && copiedBytes > 0 {
            videoImportStartedAt = Date()
        }

        videoImportProgress = min(1, max(0, fraction))
        videoImportCopiedBytes = max(0, copiedBytes)
        videoImportTotalBytes = max(0, totalBytes)
    }

    private func byteCountText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func shortDurationText(_ seconds: Double) -> String {
        let totalSeconds = max(1, Int(seconds.rounded()))
        if totalSeconds < 60 {
            return "\(totalSeconds)秒"
        }
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return remainingSeconds == 0 ? "\(minutes)分" : "\(minutes)分\(remainingSeconds)秒"
    }

    private var selectedVideoClip: TimelineVideoClip? {
        guard let selectedVideoClipID else { return nil }
        return importedVideoClips.first { $0.id == selectedVideoClipID }
    }

    private var videoTimelineTotalSeconds: Double {
        importedVideoClips.last?.endSeconds ?? 0
    }

    private func videoTimelineDurationForCurrentScope() -> Double {
        switch selectedScope {
        case .all:
            return videoTimelineTotalSeconds
        case .first:
            return min(videoTimelineTotalSeconds, Double(fullTimelineHalfDuration(for: 0)))
        case .second:
            return max(0, videoTimelineTotalSeconds - Double(fullTimelineHalfOffset(for: 1)))
        }
    }

    private var videoDeletionMessage: String {
        guard let clip = videoClipPendingDeletion ?? selectedVideoClip else {
            return "選択中の動画だけを削除します。スタッツは残ります。"
        }
        return "動画 \(clip.index + 1) だけを削除します。スタッツは残ります。"
    }

    private func configureVideoPlayerForCurrentMatch(selecting preferredClipID: String? = nil) {
        videoPlayer?.pause()
        videoPlayer = nil
        activeVideoClipID = nil
        videoClipLoadingTask?.cancel()

        let storedNames = VideoStorage.videoNames(for: match.id)
        let availableNames = storedNames.filter { VideoStorage.url(named: $0) != nil }
        if availableNames != storedNames {
            VideoStorage.setVideoNames(availableNames, for: match.id)
        }

        guard !availableNames.isEmpty else {
            importedVideoClips = []
            selectedVideoClipID = nil
            rebuildTimelinePresentationIfLoaded()
            return
        }

        videoClipLoadingTask = Task {
            var clips: [TimelineVideoClip] = []
            var timelineCursor: Double = 0

            for (index, fileName) in availableNames.enumerated() {
                guard !Task.isCancelled, let url = VideoStorage.url(named: fileName) else { continue }
                let duration = await videoDurationSeconds(for: url)
                let clip = TimelineVideoClip(
                    fileName: fileName,
                    index: index,
                    startSeconds: timelineCursor,
                    durationSeconds: max(1, duration)
                )
                clips.append(clip)
                timelineCursor = clip.endSeconds
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                importedVideoClips = clips
                selectedVideoClipID = preferredClipID
                    ?? (selectedVideoClipID.flatMap { id in clips.contains(where: { $0.id == id }) ? id : nil })
                    ?? clips.first?.id
                rebuildTimelinePresentationIfLoaded()
                seekVideo(to: playheadTimelineSecond)
            }
        }
    }

    private func rebuildTimelinePresentationIfLoaded() {
        guard didLoad else { return }
        rebuildTimelinePresentation()
    }

    private func loadMatchClockSettings() {
        matchClockSettings = TimelineMatchClockStorage.settings(for: match.id)
    }

    private func updateMatchClockSettings(_ settings: TimelineMatchClockSettings) {
        let normalizedSettings = settings.normalized()
        matchClockSettings = normalizedSettings
        TimelineMatchClockStorage.setSettings(normalizedSettings, for: match.id)
        didSetInitialPlayheadPosition = false
        rebuildTimelinePresentationIfLoaded()
        scrollToTimelineSecond(playheadTimelineSecond)
    }

    private func fullTimelineHalfDuration(for half: Int) -> Int {
        matchClockSettings.actualHalfTimelineDuration(for: half)
    }

    private func fullTimelineHalfOffset(for half: Int) -> Int {
        guard half >= 1 else { return 0 }
        return matchClockSettings.actualHalfTimelineDuration(for: 0)
    }

    private func videoDurationSeconds(for url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            return seconds.isFinite && seconds > 0 ? seconds : 1
        } catch {
            return 1
        }
    }

    private func importSelectedVideos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        stopTimelinePlayback()
        resetVideoImportProgress()
        videoImportTotalCount = items.count
        isVideoImporting = true

        Task {
            var importedFileNames: [String] = []
            do {
                for (index, item) in items.enumerated() {
                    await MainActor.run {
                        videoImportCurrentIndex = index + 1
                        videoImportProgress = 0
                        videoImportCopiedBytes = 0
                        videoImportTotalBytes = 0
                        videoImportStartedAt = nil
                    }

                    guard let movie = try await item.loadTransferable(type: TimelineImportedMovie.self) else {
                        throw TimelineVideoImportError.unavailable
                    }
                    importedFileNames.append(movie.fileName)
                }

                await MainActor.run {
                    VideoStorage.appendVideoNames(importedFileNames, for: match.id)
                    videoImportProgress = 1
                    videoImportCopiedBytes = max(videoImportCopiedBytes, videoImportTotalBytes)
                    selectedVideoItems = []
                    isVideoImporting = false
                    saveErrorMessage = nil
                    configureVideoPlayerForCurrentMatch(selecting: importedFileNames.first)
                }
            } catch {
                for fileName in importedFileNames {
                    VideoStorage.delete(named: fileName)
                }
                await MainActor.run {
                    selectedVideoItems = []
                    isVideoImporting = false
                    resetVideoImportProgress()
                    if case VideoStorageError.insufficientStorage = error {
                        saveErrorMessage = "空き容量が足りないため、動画を読み込めませんでした。"
                    } else {
                        saveErrorMessage = "動画を読み込めませんでした。別の動画で試してください。"
                    }
                }
            }
        }
    }

    private func deleteSelectedVideoClip() {
        stopTimelinePlayback()
        guard let clip = videoClipPendingDeletion ?? selectedVideoClip ?? importedVideoClips.last else { return }
        VideoStorage.removeVideoName(clip.fileName, for: match.id)
        VideoStorage.delete(named: clip.fileName)
        videoClipPendingDeletion = nil
        if selectedVideoClipID == clip.id {
            selectedVideoClipID = nil
        }
        if activeVideoClipID == clip.id {
            activeVideoClipID = nil
        }
        videoPlayer = nil
        saveErrorMessage = nil
        configureVideoPlayerForCurrentMatch()
    }

    private func seekVideo(to seconds: Double) {
        guard seconds.isFinite else { return }
        let videoSecond = videoTimelineSecond(for: seconds)
        guard let clip = videoClip(containing: videoSecond) else {
            videoPlayer?.pause()
            return
        }

        configureVideoPlayer(for: clip)
        selectedVideoClipID = clip.id

        guard let videoPlayer else { return }
        let localSecond = min(max(0, videoSecond - clip.startSeconds), clip.durationSeconds)
        let targetTime = CMTime(seconds: localSecond, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        videoPlayer.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
        if isTimelinePlaying {
            videoPlayer.play()
        }
    }

    private func syncVideoClipDuringPlayback(at timelineSecond: Double) {
        let videoSecond = videoTimelineSecond(for: timelineSecond)
        guard let clip = videoClip(containing: videoSecond) else {
            videoPlayer?.pause()
            return
        }

        if activeVideoClipID != clip.id {
            seekVideo(to: timelineSecond)
        }
    }

    private func configureVideoPlayer(for clip: TimelineVideoClip) {
        guard activeVideoClipID != clip.id || videoPlayer == nil else { return }
        videoPlayer?.pause()

        guard let url = VideoStorage.url(named: clip.fileName) else {
            activeVideoClipID = nil
            videoPlayer = nil
            return
        }

        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        videoPlayer = player
        activeVideoClipID = clip.id
    }

    private func videoTimelineSecond(for timelineSecond: Double) -> Double {
        switch selectedScope {
        case .second:
            return timelineSecond + Double(fullTimelineHalfOffset(for: 1))
        case .all, .first:
            return timelineSecond
        }
    }

    private func timelineScopeVideoStartSecond() -> Double {
        switch selectedScope {
        case .second:
            return Double(fullTimelineHalfOffset(for: 1))
        case .all, .first:
            return 0
        }
    }

    private func videoClipsForTimelineScope(maxSeconds: Int) -> [TimelineVideoClip] {
        let scopeStart = timelineScopeVideoStartSecond()
        let scopeEnd = scopeStart + Double(maxSeconds)
        return importedVideoClips.filter { clip in
            clip.endSeconds >= scopeStart && clip.startSeconds <= scopeEnd
        }
    }

    private func videoClip(containing videoSecond: Double) -> TimelineVideoClip? {
        guard !importedVideoClips.isEmpty else { return nil }
        if let clip = importedVideoClips.first(where: { videoSecond >= $0.startSeconds && videoSecond < $0.endSeconds }) {
            return clip
        }
        if let last = importedVideoClips.last, abs(videoSecond - last.endSeconds) < 0.001 {
            return last
        }
        return nil
    }

    private func updateTimelineAvailableViewportWidth(_ width: CGFloat) {
        let viewportWidth = max(220, width - 16 - timelineTrackLabelWidth)
        guard abs(timelineAvailableViewportWidth - viewportWidth) > 0.5 else { return }
        timelineAvailableViewportWidth = viewportWidth
        isTimelineOverviewMode = true
        timelineScrollOffset = 0
        playheadTimelineSecond = 0
        refreshTimelineRenderWindow(
            for: timelinePresentation,
            version: timelinePresentationVersion
        )
    }

    private func nudgePlayhead(by delta: Double, maxSeconds: Int) {
        stopTimelinePlayback()
        scrollToTimelineSecond(playheadTimelineSecond + delta, maxSeconds: maxSeconds)
    }

    private func scrollToTimelineSecond(_ second: Int, maxSeconds: Int? = nil) {
        scrollToTimelineSecond(Double(second), maxSeconds: maxSeconds)
    }

    private func scrollToTimelineSecond(_ second: Double, maxSeconds: Int? = nil, seekVideo: Bool = true) {
        let maxSeconds = maxSeconds ?? timelinePresentation.maxSeconds
        let clampedSecond = min(max(0, second), Double(maxSeconds))
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)
        let viewportWidth = max(timelineRenderedViewportWidth, timelineViewportFrame.width)
        let targetX = xOffset(for: clampedSecond, maxSeconds: maxSeconds, contentWidth: contentWidth)

        playheadTimelineSecond = clampedSecond
        if seekVideo {
            pendingScrollSeekTask?.cancel()
            self.seekVideo(to: clampedSecond)
        }
        guard viewportWidth > 0 else { return }

        updateTimelineScrollOffsetFromPlayhead(
            clampedTimelineScrollOffset(
                targetX - viewportWidth / 2,
                contentWidth: contentWidth,
                viewportWidth: viewportWidth
            )
        )
    }

    private func updateTimelineScrollOffsetFromPlayhead(_ offset: CGFloat) {
        isTimelineScrollSyncSuppressed = true
        timelineScrollOffset = offset
        Task { @MainActor in
            await Task.yield()
            isTimelineScrollSyncSuppressed = false
        }
    }

    private func syncPlayheadWithScroll() {
        let maxSeconds = timelinePresentation.maxSeconds
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)
        let viewportWidth = max(timelineRenderedViewportWidth, timelineViewportFrame.width)
        guard viewportWidth > 0 else { return }

        let markerX = min(contentWidth, max(0, timelineScrollOffset + viewportWidth / 2))
        let second = Double(timelineSecond(forContentX: markerX, maxSeconds: maxSeconds, contentWidth: contentWidth))
        let clampedSecond = min(max(0, second), Double(maxSeconds))
        playheadTimelineSecond = clampedSecond
        if !isTimelinePlaying {
            scheduleScrollSeek(to: clampedSecond)
        }
    }

    private func scheduleScrollSeek(to seconds: Double) {
        pendingScrollSeekTask?.cancel()
        pendingScrollSeekTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, !isTimelinePlaying else { return }
            seekVideo(to: seconds)
        }
    }

    private func positionInitialPlayheadIfNeeded(maxSeconds: Int, contentWidth: CGFloat) {
        guard !didSetInitialPlayheadPosition else { return }
        let viewportWidth = max(timelineRenderedViewportWidth, timelineViewportFrame.width)
        guard viewportWidth > 0 else { return }

        didSetInitialPlayheadPosition = true
        isTimelineOverviewMode = true
        playheadTimelineSecond = 0
        timelineScrollOffset = 0
    }

    private var pointsPerSecond: CGFloat {
        2.4 * timelineZoom
    }

    private var zoomText: String {
        String(format: "x%.1f", Double(timelineZoom))
    }

    private var timelineZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                isTimelineOverviewMode = false
                timelineZoom = clampedTimelineZoom(baseTimelineZoom * value)
            }
            .onEnded { value in
                setTimelineZoom(baseTimelineZoom * value)
            }
    }

    private func setTimelineZoom(_ zoom: CGFloat) {
        isTimelineOverviewMode = zoom <= minimumTimelineZoom
        timelineZoom = clampedTimelineZoom(zoom)
        baseTimelineZoom = timelineZoom
    }

    private func clampedTimelineZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumTimelineZoom, max(minimumTimelineZoom, zoom))
    }

    private func clampedTimelineSecond(for event: StatEvent, proposedSecond: Int) -> Int {
        let halfStart = halfTimelineOffset(for: event.half)
        let halfEnd = halfStart + timelinePresentation.halfDuration(for: event.half)
        let latestStart: Int
        if event.category == "possession" {
            let latestClockStart = max(0, matchClockSettings.clockDuration(for: event.half) - max(1, event.seconds))
            latestStart = halfStart + matchClockSettings.timelineSecond(forClockSecond: latestClockStart, half: event.half)
        } else {
            latestStart = halfEnd
        }
        return min(max(halfStart, proposedSecond), latestStart)
    }

    private func timelineLocalSeconds(from timelineSecond: Int, half: Int) -> Int {
        let localTimelineSecond = max(0, timelineSecond - halfTimelineOffset(for: half))
        return matchClockSettings.clockSecond(fromTimelineSecond: localTimelineSecond, half: half)
    }

    private func timelineStartSeconds(for event: StatEvent) -> Int {
        timelinePresentation.timelineStartSeconds[event.id] ?? calculatedTimelineStartSecond(
            for: event,
            halfOffsets: timelinePresentation.halfOffsets,
            inferredPossessionStarts: timelinePresentation.inferredPossessionStarts
        )
    }

    private func halfTimelineOffset(for half: Int) -> Int {
        timelinePresentation.halfOffset(for: half)
    }

    private func possessionTotalSeconds(for visibleEvents: [StatEvent], includesBIP: Bool) -> Int {
        visibleEvents
            .filter { event in
                event.category == "possession" && ((event.outcome == "none") == includesBIP)
            }
            .reduce(0) { $0 + max(0, $1.seconds) }
    }

    private func timelineRulerText(for timelineSecond: Int) -> String {
        guard selectedScope == .all else {
            return timeText(timelineSecond)
        }

        let secondHalfOffset = halfTimelineOffset(for: 1)
        if timelineSecond >= secondHalfOffset {
            return timeText(timelineSecond - secondHalfOffset)
        }
        return timeText(timelineSecond)
    }

    private func halfDivider(
        maxSeconds: Int,
        contentWidth: CGFloat,
        scrollOffset: CGFloat,
        height: CGFloat = 34
    ) -> some View {
        Rectangle()
            .fill(Color.blue.opacity(0.75))
            .frame(width: 2, height: height)
            .offset(x: xOffset(for: halfTimelineOffset(for: 1), maxSeconds: maxSeconds, contentWidth: contentWidth) - scrollOffset)
    }

    private func halfChangeLabel(maxSeconds: Int, contentWidth: CGFloat, scrollOffset: CGFloat) -> some View {
        Text("後半開始")
            .font(.caption2.weight(.black))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Color.blue.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .offset(
                x: xOffset(for: halfTimelineOffset(for: 1), maxSeconds: maxSeconds, contentWidth: contentWidth) - scrollOffset + 5,
                y: 11
            )
    }

    private func timelineContentWidth(maxSeconds: Int) -> CGFloat {
        let viewportWidth = timelineScrollViewportWidth()
        let playableWidth = isTimelineOverviewMode
            ? viewportWidth
            : max(viewportWidth, CGFloat(maxSeconds) * pointsPerSecond)
        return playableWidth + viewportWidth
    }

    private func timelineScrollViewportWidth() -> CGFloat {
        max(
            1,
            max(timelineRenderedViewportWidth, max(timelineViewportFrame.width, max(220, timelineAvailableViewportWidth)))
        )
    }

    private func timelinePlayableContentWidth(maxSeconds: Int, contentWidth: CGFloat) -> CGFloat {
        max(1, contentWidth - timelineScrollViewportWidth())
    }

    private func timelinePlayheadContentInset() -> CGFloat {
        timelineScrollViewportWidth() / 2
    }

    private func timelineSecond(forContentX contentX: CGFloat, maxSeconds: Int, contentWidth: CGFloat) -> CGFloat {
        let playableWidth = timelinePlayableContentWidth(maxSeconds: maxSeconds, contentWidth: contentWidth)
        let second = (contentX - timelinePlayheadContentInset()) / playableWidth * CGFloat(max(maxSeconds, 1))
        return min(CGFloat(maxSeconds), max(0, second))
    }

    private func timelineTicks(maxSeconds: Int) -> [Int] {
        let interval = timelineTickInterval(maxSeconds: maxSeconds)
        return stride(from: 0, through: maxSeconds, by: interval).map { $0 }
    }

    private func visibleTimelineTicks(
        maxSeconds: Int,
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        scrollOffset: CGFloat
    ) -> [Int] {
        guard viewportWidth > 0 else {
            return Array(timelineTicks(maxSeconds: maxSeconds).prefix(12))
        }

        let interval = timelineTickInterval(maxSeconds: maxSeconds)
        let pointsPerSecond = max(timelinePointsPerSecond(maxSeconds: maxSeconds, contentWidth: contentWidth), 0.1)
        let bufferPixels = timelineRenderPadding + timelineRenderBucketWidth
        let bufferSeconds = max(interval, Int((bufferPixels / pointsPerSecond).rounded(.up)))
        let visibleStart = max(
            0,
            Int(timelineSecond(forContentX: scrollOffset, maxSeconds: maxSeconds, contentWidth: contentWidth).rounded(.down)) - bufferSeconds
        )
        let visibleEnd = min(
            maxSeconds,
            Int(timelineSecond(forContentX: scrollOffset + viewportWidth, maxSeconds: maxSeconds, contentWidth: contentWidth).rounded(.up)) + bufferSeconds
        )
        let firstTick = max(0, (visibleStart / interval) * interval)

        return stride(from: firstTick, through: visibleEnd, by: interval).map { $0 }
    }

    private func visibleTimelineMinorTicks(
        maxSeconds: Int,
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        scrollOffset: CGFloat
    ) -> [Int] {
        guard viewportWidth > 0 else { return [] }

        let interval = max(30, timelineTickInterval(maxSeconds: maxSeconds) / 5)
        let pointsPerSecond = max(timelinePointsPerSecond(maxSeconds: maxSeconds, contentWidth: contentWidth), 0.1)
        let bufferPixels = timelineRenderPadding + timelineRenderBucketWidth
        let bufferSeconds = max(interval, Int((bufferPixels / pointsPerSecond).rounded(.up)))
        let visibleStart = max(
            0,
            Int(timelineSecond(forContentX: scrollOffset, maxSeconds: maxSeconds, contentWidth: contentWidth).rounded(.down)) - bufferSeconds
        )
        let visibleEnd = min(
            maxSeconds,
            Int(timelineSecond(forContentX: scrollOffset + viewportWidth, maxSeconds: maxSeconds, contentWidth: contentWidth).rounded(.up)) + bufferSeconds
        )
        let firstTick = max(0, (visibleStart / interval) * interval)

        return stride(from: firstTick, through: visibleEnd, by: interval).map { $0 }
    }

    private var timelineScrollMarkerInterval: Int {
        10
    }

    private func nearestTimelineScrollMarker(for second: Int, maxSeconds: Int) -> Int {
        let clamped = min(max(0, second), maxSeconds)
        return Int((Double(clamped) / Double(timelineScrollMarkerInterval)).rounded()) * timelineScrollMarkerInterval
    }

    private func timelineTickInterval(maxSeconds: Int) -> Int {
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)
        let effectivePointsPerSecond = timelinePointsPerSecond(maxSeconds: maxSeconds, contentWidth: contentWidth)
        let targetSeconds = 70 / max(effectivePointsPerSecond, 0.1)
        let candidates = [10, 15, 30, 60, 120, 180, 300, 600]
        return candidates.first { Double($0) >= Double(targetSeconds) } ?? 600
    }

    private func timelinePointsPerSecond(maxSeconds: Int, contentWidth: CGFloat) -> CGFloat {
        timelinePlayableContentWidth(maxSeconds: maxSeconds, contentWidth: contentWidth) / CGFloat(max(maxSeconds, 1))
    }


    private func xOffset(for seconds: Int, maxSeconds: Int, contentWidth: CGFloat) -> CGFloat {
        xOffset(for: Double(seconds), maxSeconds: maxSeconds, contentWidth: contentWidth)
    }

    private func xOffset(for seconds: Double, maxSeconds: Int, contentWidth: CGFloat) -> CGFloat {
        timelinePlayheadContentInset()
            + CGFloat(min(max(0, seconds), Double(maxSeconds))) / CGFloat(max(maxSeconds, 1))
            * timelinePlayableContentWidth(maxSeconds: maxSeconds, contentWidth: contentWidth)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("記録データを読み込み中")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func teamColumn(teamID: UUID, label: String, accent: Color) -> some View {
        VStack(spacing: 5) {
            teamLogoBox(teamID: teamID, size: 46)
            Text(teamName(for: teamID))
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label)
                .font(.caption2.weight(.black))
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(accent.opacity(0.22))
                .clipShape(Capsule())
        }
        .frame(width: 82)
    }

    @ViewBuilder
    private func teamLogoBox(teamID: UUID, size: CGFloat) -> some View {
        let team = teams.first { $0.id == teamID }
        Group {
            if let team, let name = team.logoPath, let uiImage = ImageStorage.image(named: name) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "shield.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func scoreChip(_ title: String, half: Int) -> some View {
        Text("\(title) \(score(for: match.homeTeamID, half: half))-\(score(for: match.awayTeamID, half: half))")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.64))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
    }

    private func metricChip(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.black))
            Text("\(count)")
                .font(.caption.weight(.black).monospacedDigit())
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }

    private func trackBadge(_ track: TimelineTrackDefinition, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: track.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(track.color)
            Text(track.title)
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(track.color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func eventRow(
        _ event: StatEvent,
        progression: (home: Int, away: Int)?,
        playerLookup: [UUID: Player]
    ) -> some View {
        let category = timelineCategory(for: event)
        let accent = categoryColor(for: event)

        return Button {
            selectedEvent = event
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(halfLabel(event.half))
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white.opacity(0.48))
                    Text(timeText(event.seconds))
                        .font(.headline.weight(.black).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(category?.shortTitle ?? event.category.uppercased())
                            .font(.caption.weight(.black))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text(teamLabel(for: event))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(teamColor(for: event).opacity(0.9))
                    }

                    Text(playerName(for: event.playerID, in: playerLookup, fallback: category?.detailFallback ?? "選手なし"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(scoreImpactText(for: event))
                        .font(.caption.weight(.black).monospacedDigit())
                        .foregroundStyle(scoreImpactColor(for: event))
                    Text(scoreText(for: event, progression: progression))
                        .font(.subheadline.weight(.black).monospacedDigit())
                        .foregroundStyle(.white)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(10)
            .background(Color.black.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                requestDeleteTimelineEvent(event)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    @MainActor
    private func loadDataIfNeeded() async {
        guard !didLoad else { return }
        try? await Task.sleep(for: .milliseconds(60))
        guard !Task.isCancelled else { return }
        reloadData()
    }

    private func rebuildTimelinePresentation() {
        let presentation = makeTimelinePresentation()
        let version = timelinePresentationVersion + 1
        timelinePresentation = presentation
        timelinePresentationVersion = version
        refreshTimelineRenderWindow(for: presentation, version: version)
        if let selectedTimelineEventID,
           !presentation.visibleEvents.contains(where: { $0.id == selectedTimelineEventID }) {
            self.selectedTimelineEventID = nil
        }
    }

    private func makeTimelinePresentation() -> TimelinePresentationState {
        let inferredPossessionStarts = buildInferredPossessionStarts(from: events)
        let visibleEvents = sortedEditableEvents(
            from: events,
            half: selectedScope.half,
            inferredPossessionStarts: inferredPossessionStarts
        )
        let scoringEvents = sortedScoringEvents(from: events)
        let scoringProgression = buildScoringProgression(from: scoringEvents)
        let playerLookup = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        let halfDurations = [
            0: calculatedHalfTimelineDuration(0, in: visibleEvents),
            1: calculatedHalfTimelineDuration(1, in: visibleEvents)
        ]
        let halfOffsets = [
            0: 0,
            1: selectedScope == .all ? halfDurations[0, default: 60] : 0
        ]
        let rawMaxSeconds: Int
        if let half = selectedScope.half {
            rawMaxSeconds = halfDurations[half, default: 60]
        } else {
            rawMaxSeconds = halfDurations[0, default: 60] + halfDurations[1, default: 60]
        }
        let baselineSeconds = selectedScope == .all
            ? matchClockSettings.actualHalfTimelineDuration(for: 0) + matchClockSettings.actualHalfTimelineDuration(for: 1)
            : matchClockSettings.actualHalfTimelineDuration(for: selectedScope.half ?? 0)
        let videoMaxSeconds = Int(ceil(videoTimelineDurationForCurrentScope()))
        let roundedMaxSeconds = Int(ceil(Double(max(rawMaxSeconds, baselineSeconds, videoMaxSeconds)) / 60.0)) * 60
        let timelineStartSeconds = Dictionary(uniqueKeysWithValues: visibleEvents.map { event in
            (
                event.id,
                calculatedTimelineStartSecond(
                    for: event,
                    halfOffsets: halfOffsets,
                    inferredPossessionStarts: inferredPossessionStarts
                )
            )
        })

        var trackEvents: [String: [StatEvent]] = [:]
        var trackRenderEvents: [String: [TimelineRenderEvent]] = [:]
        var trackCounts: [String: Int] = [:]
        for track in trackDefinitions {
            let matches = visibleEvents.filter { track.matches($0, match) }
            trackEvents[track.id] = matches
            trackRenderEvents[track.id] = matches.map { event in
                let startSeconds = timelineStartSeconds[event.id] ?? calculatedTimelineStartSecond(
                    for: event,
                    halfOffsets: halfOffsets,
                    inferredPossessionStarts: inferredPossessionStarts
                )
                return makeTimelineRenderEvent(
                    from: event,
                    startSeconds: startSeconds,
                    endSeconds: calculatedTimelineEndSecond(
                        for: event,
                        halfOffsets: halfOffsets,
                        inferredPossessionStarts: inferredPossessionStarts
                    )
                )
            }
            trackCounts[track.id] = matches.count
        }

        return TimelinePresentationState(
            visibleEvents: visibleEvents,
            scoringEvents: scoringEvents,
            scoringProgression: scoringProgression,
            playerLookup: playerLookup,
            trackEvents: trackEvents,
            trackRenderEvents: trackRenderEvents,
            trackCounts: trackCounts,
            scoringCount: visibleEvents.filter { ScoringCategory(rawValue: $0.category) != nil }.count,
            setPieceCount: visibleEvents.filter { $0.category == "lineout" || $0.category == "scrum" }.count,
            possessionCount: visibleEvents.filter { $0.category == "possession" }.count,
            halfDurations: halfDurations,
            halfOffsets: halfOffsets,
            maxSeconds: max(60, roundedMaxSeconds),
            inferredPossessionStarts: inferredPossessionStarts,
            timelineStartSeconds: timelineStartSeconds
        )
    }

    private func reloadData() {
        do {
            let matchID = match.id
            let homeID = match.homeTeamID
            let awayID = match.awayTeamID

            let eventDescriptor = FetchDescriptor<StatEvent>(
                predicate: #Predicate<StatEvent> { event in
                    event.matchID == matchID
                }
            )
            var playerDescriptor = FetchDescriptor<Player>(
                predicate: #Predicate<Player> { player in
                    player.teamID == homeID || player.teamID == awayID
                }
            )
            playerDescriptor.sortBy = [SortDescriptor(\Player.number)]

            loadMatchClockSettings()
            events = try modelContext.fetch(eventDescriptor)
            players = try modelContext.fetch(playerDescriptor)
            teams = try modelContext.fetch(FetchDescriptor<Team>())
            setTimelineZoom(minimumTimelineZoom)
            didSetInitialPlayheadPosition = false
            rebuildTimelinePresentation()
            didLoad = true
        } catch {
            loadMatchClockSettings()
            events = []
            players = []
            teams = []
            setTimelineZoom(minimumTimelineZoom)
            didSetInitialPlayheadPosition = false
            rebuildTimelinePresentation()
            didLoad = true
        }
    }

    private func sortedScoringEvents(from source: [StatEvent]) -> [StatEvent] {
        source
            .filter { ScoringCategory(rawValue: $0.category) != nil }
            .sorted { lhs, rhs in
                if lhs.half != rhs.half { return lhs.half < rhs.half }
                if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
                return eventSortRank(lhs.category, outcome: lhs.outcome) < eventSortRank(rhs.category, outcome: rhs.outcome)
            }
    }

    private func buildScoringProgression(from scoringEvents: [StatEvent]) -> [UUID: (home: Int, away: Int)] {
        var home = 0
        var away = 0
        var progression: [UUID: (home: Int, away: Int)] = [:]

        for event in scoringEvents {
            let value = scoreValue(for: event)
            if event.teamID == match.homeTeamID {
                home += value
            } else if event.teamID == match.awayTeamID {
                away += value
            }
            progression[event.id] = (home, away)
        }

        return progression
    }

    private func buildInferredPossessionStarts(from source: [StatEvent]) -> [UUID: Int] {
        var starts: [UUID: Int] = [:]

        for half in [0, 1] {
            for includesBIP in [false, true] {
                var start = 0
                for event in source where event.category == "possession"
                    && event.half == half
                    && ((event.outcome == "none") == includesBIP) {
                    starts[event.id] = start
                    start += max(0, event.seconds)
                }
            }
        }

        return starts
    }

    private func calculatedHalfTimelineDuration(_ half: Int, in visibleEvents: [StatEvent]) -> Int {
        let halfEvents = visibleEvents.filter { $0.half == half }
        let maxPointSeconds = halfEvents
            .filter { $0.category != "possession" }
            .map { matchClockSettings.timelineSecond(forClockSecond: $0.seconds, half: half) }
            .max() ?? 0
        let maxStoredPossessionEnd = halfEvents
            .filter { $0.category == "possession" }
            .compactMap { event in
                event.startSeconds.map {
                    matchClockSettings.timelineSecond(
                        forClockSecond: $0 + max(0, event.seconds),
                        half: half
                    )
                }
            }
            .max() ?? 0
        let homeAwayDuration = possessionTotalSeconds(
            for: halfEvents,
            includesBIP: false
        )
        let bipDuration = possessionTotalSeconds(
            for: halfEvents,
            includesBIP: true
        )
        return max(
            maxPointSeconds,
            maxStoredPossessionEnd,
            matchClockSettings.timelineSecond(forClockSecond: homeAwayDuration, half: half),
            matchClockSettings.timelineSecond(forClockSecond: bipDuration, half: half),
            matchClockSettings.actualHalfTimelineDuration(for: half)
        )
    }

    private func calculatedTimelineStartSecond(
        for event: StatEvent,
        halfOffsets: [Int: Int],
        inferredPossessionStarts: [UUID: Int]
    ) -> Int {
        let halfOffset = halfOffsets[event.half, default: 0]
        if event.category == "possession" {
            let clockSecond = event.startSeconds ?? inferredPossessionStarts[event.id] ?? 0
            return halfOffset + matchClockSettings.timelineSecond(forClockSecond: clockSecond, half: event.half)
        }
        return halfOffset + matchClockSettings.timelineSecond(forClockSecond: event.seconds, half: event.half)
    }

    private func calculatedTimelineEndSecond(
        for event: StatEvent,
        halfOffsets: [Int: Int],
        inferredPossessionStarts: [UUID: Int]
    ) -> Int {
        guard event.category == "possession" else {
            return calculatedTimelineStartSecond(
                for: event,
                halfOffsets: halfOffsets,
                inferredPossessionStarts: inferredPossessionStarts
            )
        }

        let halfOffset = halfOffsets[event.half, default: 0]
        let startClockSecond = event.startSeconds ?? inferredPossessionStarts[event.id] ?? 0
        let endClockSecond = startClockSecond + max(1, event.seconds)
        return halfOffset + matchClockSettings.timelineSecond(forClockSecond: endClockSecond, half: event.half)
    }

    private func makeTimelineRenderEvent(from event: StatEvent, startSeconds: Int, endSeconds: Int) -> TimelineRenderEvent {
        let isDuration = event.category == "possession"
        let durationSeconds = isDuration ? max(1, endSeconds - startSeconds) : max(1, event.seconds)
        return TimelineRenderEvent(
            event: event,
            startSeconds: startSeconds,
            endSeconds: isDuration ? max(startSeconds + 1, endSeconds) : startSeconds,
            durationSeconds: durationSeconds,
            isDuration: isDuration,
            title: timelineCategory(for: event)?.shortTitle ?? event.category.uppercased(),
            pointDetail: isDuration ? nil : scoreImpactText(for: event),
            isFailed: event.outcome == "fail"
        )
    }

    private func adjust(_ event: StatEvent, by delta: Int) -> Int {
        let previousSeconds = event.seconds
        event.seconds = max(0, event.seconds + delta)

        do {
            try modelContext.save()
            saveErrorMessage = nil
            let inferredPossessionStarts = buildInferredPossessionStarts(from: events)
            events = sortedEditableEvents(
                from: events,
                half: nil,
                inferredPossessionStarts: inferredPossessionStarts
            ) + events.filter { timelineCategory(for: $0) == nil }
            rebuildTimelinePresentation()
        } catch {
            event.seconds = previousSeconds
            rebuildTimelinePresentation()
            saveErrorMessage = "時刻の変更を保存できませんでした。もう一度試してください。"
        }

        return event.seconds
    }

    private func sortedEditableEvents(
        from source: [StatEvent],
        half: Int?,
        inferredPossessionStarts: [UUID: Int]? = nil
    ) -> [StatEvent] {
        let inferredPossessionStarts = inferredPossessionStarts ?? timelinePresentation.inferredPossessionStarts
        return source
            .filter { timelineCategory(for: $0) != nil }
            .filter { half == nil || $0.half == half }
            .sorted { lhs, rhs in
                if lhs.half != rhs.half { return lhs.half < rhs.half }
                let lhsSecond = timelineSortSecond(for: lhs, inferredPossessionStarts: inferredPossessionStarts)
                let rhsSecond = timelineSortSecond(for: rhs, inferredPossessionStarts: inferredPossessionStarts)
                if lhsSecond != rhsSecond { return lhsSecond < rhsSecond }
                return eventSortRank(lhs.category, outcome: lhs.outcome) < eventSortRank(rhs.category, outcome: rhs.outcome)
            }
    }

    private func timelineSortSecond(for event: StatEvent, inferredPossessionStarts: [UUID: Int]) -> Int {
        if event.category == "possession" {
            return event.startSeconds ?? inferredPossessionStarts[event.id] ?? 0
        }
        return event.seconds
    }

    private func score(for teamID: UUID, half: Int? = nil) -> Int {
        scoringEvents
            .filter { event in
                event.teamID == teamID && (half == nil || event.half == half)
            }
            .reduce(0) { $0 + scoreValue(for: $1) }
    }

    private func scoreValue(for event: StatEvent) -> Int {
        guard event.outcome == "success" else { return 0 }
        switch ScoringCategory(rawValue: event.category) {
        case .tryScore: return 5
        case .conversion: return 2
        case .penaltyGoal, .dropGoal: return 3
        case nil: return 0
        }
    }

    private func teamName(for id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "チーム未設定"
    }

    private func players(forTeamID teamID: UUID) -> [Player] {
        players
            .filter { $0.teamID == teamID }
            .sorted { lhs, rhs in
                if lhs.number != rhs.number { return lhs.number < rhs.number }
                return (lhs.name ?? "") < (rhs.name ?? "")
            }
    }

    private func playerName(for playerID: UUID?, in lookup: [UUID: Player], fallback: String) -> String {
        guard let playerID, let player = lookup[playerID] else {
            return fallback
        }
        if let name = player.name, !name.isEmpty {
            return "#\(player.number) \(name)"
        }
        return "#\(player.number) 名前未設定"
    }

    private func halfLabel(_ half: Int) -> String {
        half >= 1 ? "後半" : "前半"
    }

    private func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func timeText(_ seconds: Double) -> String {
        let totalTenths = Int((max(0, seconds) * 10).rounded())
        let minutes = totalTenths / 600
        let wholeSeconds = (totalTenths / 10) % 60
        let tenths = totalTenths % 10
        return String(format: "%02d:%02d.%d", minutes, wholeSeconds, tenths)
    }

    private func teamLabel(for event: StatEvent) -> String {
        if event.teamID == match.homeTeamID { return "HOME" }
        if event.teamID == match.awayTeamID { return "AWAY" }
        return "-"
    }

    private func teamColor(for event: StatEvent) -> Color {
        if event.teamID == match.homeTeamID { return .blue }
        if event.teamID == match.awayTeamID { return .red }
        return .white.opacity(0.62)
    }

    private func outcomeText(for event: StatEvent) -> String {
        if event.category == "possession" {
            return event.outcome == "none" ? "BIP" : "区間"
        }
        switch event.outcome {
        case "success": return "成功"
        case "fail": return "失敗"
        default: return event.outcome
        }
    }

    private func outcomeColor(for event: StatEvent) -> Color {
        switch event.outcome {
        case "success": return .green
        case "fail": return .orange
        default: return .white.opacity(0.56)
        }
    }

    private func scoreImpactText(for event: StatEvent) -> String {
        guard ScoringCategory(rawValue: event.category) != nil else {
            return outcomeText(for: event)
        }
        return "+\(scoreValue(for: event))点"
    }

    private func scoreImpactColor(for event: StatEvent) -> Color {
        guard ScoringCategory(rawValue: event.category) != nil else {
            return outcomeColor(for: event)
        }
        return scoreValue(for: event) > 0 ? .green : .orange
    }

    private func scoreText(for event: StatEvent, progression: (home: Int, away: Int)?) -> String {
        guard ScoringCategory(rawValue: event.category) != nil, let progression else {
            return "-"
        }
        return "\(progression.home)-\(progression.away)"
    }

    private func editorTitle(for event: StatEvent) -> String {
        event.category == "possession" ? "区間時間" : "イベント時刻"
    }

    private func eventTitle(for event: StatEvent) -> String {
        timelineCategory(for: event)?.title ?? event.category
    }

    private func eventSubtitle(for event: StatEvent) -> String {
        let lookup = playerLookup
        let fallback = timelineCategory(for: event)?.detailFallback ?? "選手なし"
        return "\(halfLabel(event.half)) / \(teamLabel(for: event)) / \(playerName(for: event.playerID, in: lookup, fallback: fallback))"
    }

    private func timelineCategory(for event: StatEvent) -> TimelineEventCategory? {
        if event.category == "possession" {
            if event.outcome == "none" { return .bip }
            if event.teamID == match.homeTeamID { return .homePossession }
            if event.teamID == match.awayTeamID { return .awayPossession }
            if event.outcome == "own" { return .homePossession }
            if event.outcome == "opponent" { return .awayPossession }
        }
        if let scoring = ScoringCategory(rawValue: event.category) {
            switch scoring {
            case .tryScore: return .tryScore
            case .conversion: return .conversion
            case .penaltyGoal: return .penaltyGoal
            case .dropGoal: return .dropGoal
            }
        }
        switch event.category {
        case "lineout": return .lineout
        case "scrum": return .scrum
        default: return nil
        }
    }

    private func categoryColor(for event: StatEvent) -> Color {
        timelineCategory(for: event)?.color ?? .secondary
    }

    private func eventSortRank(_ category: String, outcome: String) -> Int {
        switch category {
        case "try": return 0
        case "conversion": return 1
        case "penalty_goal": return 2
        case "drop_goal": return 3
        case "lineout": return 4
        case "scrum": return 5
        case "possession" where outcome == "none": return 6
        case "possession": return 7
        default: return 99
        }
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

private struct RugbyVideoPreview: View {
    private let players: [PreviewPlayerMarker] = [
        PreviewPlayerMarker(id: 1, x: 0.16, y: 0.72, isHome: true),
        PreviewPlayerMarker(id: 2, x: 0.21, y: 0.66, isHome: true),
        PreviewPlayerMarker(id: 3, x: 0.25, y: 0.58, isHome: true),
        PreviewPlayerMarker(id: 4, x: 0.31, y: 0.51, isHome: true),
        PreviewPlayerMarker(id: 5, x: 0.36, y: 0.44, isHome: true),
        PreviewPlayerMarker(id: 6, x: 0.40, y: 0.35, isHome: true),
        PreviewPlayerMarker(id: 7, x: 0.26, y: 0.79, isHome: true),
        PreviewPlayerMarker(id: 8, x: 0.42, y: 0.58, isHome: true),
        PreviewPlayerMarker(id: 9, x: 0.64, y: 0.24, isHome: false),
        PreviewPlayerMarker(id: 10, x: 0.70, y: 0.31, isHome: false),
        PreviewPlayerMarker(id: 11, x: 0.76, y: 0.38, isHome: false),
        PreviewPlayerMarker(id: 12, x: 0.82, y: 0.47, isHome: false),
        PreviewPlayerMarker(id: 13, x: 0.88, y: 0.56, isHome: false),
        PreviewPlayerMarker(id: 14, x: 0.73, y: 0.61, isHome: false),
        PreviewPlayerMarker(id: 15, x: 0.56, y: 0.42, isHome: false),
        PreviewPlayerMarker(id: 16, x: 0.52, y: 0.28, isHome: false),
        PreviewPlayerMarker(id: 17, x: 0.48, y: 0.33, isHome: false)
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.48, blue: 0.13),
                        Color(red: 0.31, green: 0.62, blue: 0.20),
                        Color(red: 0.17, green: 0.43, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 0) {
                    stadiumBand
                        .frame(height: size.height * 0.18)
                    Spacer(minLength: 0)
                }

                pitchLines(size: size)
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)

                ForEach(players) { marker in
                    previewPlayer(isHome: marker.isHome)
                        .position(x: marker.x * size.width, y: marker.y * size.height)
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.black.opacity(0.18), .clear, .black.opacity(0.16)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private var stadiumBand: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.13),
                    Color(red: 0.85, green: 0.17, blue: 0.08),
                    Color(red: 0.05, green: 0.06, blue: 0.10)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(spacing: 7) {
                ForEach(0..<12, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index.isMultiple(of: 3) ? Color.white.opacity(0.88) : Color.black.opacity(0.48))
                        .frame(width: index.isMultiple(of: 4) ? 34 : 24, height: 9)
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func pitchLines(size: CGSize) -> Path {
        var path = Path()
        let width = size.width
        let height = size.height
        let top = height * 0.18
        let bottom = height * 0.95

        path.move(to: CGPoint(x: width * 0.12, y: top))
        path.addLine(to: CGPoint(x: width * 0.03, y: bottom))
        path.move(to: CGPoint(x: width * 0.94, y: top))
        path.addLine(to: CGPoint(x: width * 0.98, y: bottom))
        path.move(to: CGPoint(x: width * 0.50, y: top))
        path.addLine(to: CGPoint(x: width * 0.50, y: bottom))
        path.move(to: CGPoint(x: width * 0.28, y: top))
        path.addLine(to: CGPoint(x: width * 0.20, y: bottom))
        path.move(to: CGPoint(x: width * 0.73, y: top))
        path.addLine(to: CGPoint(x: width * 0.80, y: bottom))
        path.move(to: CGPoint(x: width * 0.04, y: height * 0.52))
        path.addLine(to: CGPoint(x: width * 0.98, y: height * 0.48))

        return path
    }

    private func previewPlayer(isHome: Bool) -> some View {
        VStack(spacing: 1) {
            Circle()
                .fill(Color(red: 0.90, green: 0.70, blue: 0.54))
                .frame(width: 4, height: 4)
            RoundedRectangle(cornerRadius: 2)
                .fill(isHome ? Color(red: 0.82, green: 0.05, blue: 0.07) : Color.white)
                .frame(width: 10, height: 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isHome ? Color.white.opacity(0.88) : Color(red: 0.05, green: 0.14, blue: 0.36))
                        .frame(height: 3)
                }
        }
        .frame(width: 15, height: 20)
        .shadow(color: .black.opacity(0.32), radius: 2, x: 0, y: 1)
    }
}

private struct PreviewPlayerMarker: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let isHome: Bool
}

private struct TimelineNativeScrollViewport<Content: View>: UIViewRepresentable {
    let contentWidth: CGFloat
    let viewportHeight: CGFloat
    let renderBucketWidth: CGFloat
    let hostOrigin: CGFloat
    let hostWidth: CGFloat
    let contentIdentity: AnyHashable
    @Binding var scrollOffset: CGFloat
    let onViewportFrameChange: (CGRect) -> Void
    let onRenderFrameChange: (CGFloat, CGFloat) -> Void
    let content: () -> Content

    init(
        contentWidth: CGFloat,
        viewportHeight: CGFloat,
        renderBucketWidth: CGFloat = 360,
        hostOrigin: CGFloat,
        hostWidth: CGFloat,
        contentIdentity: AnyHashable = 0,
        scrollOffset: Binding<CGFloat>,
        onViewportFrameChange: @escaping (CGRect) -> Void,
        onRenderFrameChange: @escaping (CGFloat, CGFloat) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.contentWidth = contentWidth
        self.viewportHeight = viewportHeight
        self.renderBucketWidth = renderBucketWidth
        self.hostOrigin = hostOrigin
        self.hostWidth = hostWidth
        self.contentIdentity = contentIdentity
        _scrollOffset = scrollOffset
        self.onViewportFrameChange = onViewportFrameChange
        self.onRenderFrameChange = onRenderFrameChange
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.clipsToBounds = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.contentSize = CGSize(width: max(1, contentWidth), height: viewportHeight)

        let host = UIHostingController(rootView: hostedContent)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = true
        scrollView.addSubview(host.view)

        context.coordinator.host = host
        context.coordinator.lastHostedContentKey = hostedContentKey
        context.coordinator.updateHostedFrame(in: scrollView)

        DispatchQueue.main.async {
            context.coordinator.reportViewport(scrollView)
            context.coordinator.reportRenderWindow(scrollView, force: true)
        }

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // setContentOffset 等で delegate が同期的に呼ばれても
        // SwiftUI の画面更新中に状態を書き換えないようにするフラグ
        context.coordinator.isPerformingViewUpdate = true
        defer { context.coordinator.isPerformingViewUpdate = false }

        context.coordinator.parent = self
        let contentKey = hostedContentKey
        if context.coordinator.lastHostedContentKey != contentKey {
            context.coordinator.host?.rootView = hostedContent
            context.coordinator.lastHostedContentKey = contentKey
        }
        context.coordinator.updateHostedFrame(in: scrollView)

        let maxOffset = max(0, contentWidth - scrollView.bounds.width)
        let desiredOffset = min(max(0, scrollOffset), maxOffset)
        if !scrollView.isDragging,
           !scrollView.isDecelerating,
           abs(scrollView.contentOffset.x - desiredOffset) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: desiredOffset, y: 0), animated: false)
        }

        DispatchQueue.main.async {
            context.coordinator.reportViewport(scrollView)
            context.coordinator.reportRenderWindow(scrollView, force: false)
        }
    }

    private var hostedContent: AnyView {
        AnyView(
            content()
                .frame(width: max(1, hostWidth), height: viewportHeight, alignment: .topLeading)
        )
    }

    private var hostedContentKey: HostedContentKey {
        HostedContentKey(
            identity: contentIdentity,
            hostWidth: Int(max(1, hostWidth).rounded()),
            viewportHeight: Int(max(1, viewportHeight).rounded())
        )
    }

    struct HostedContentKey: Equatable {
        let identity: AnyHashable
        let hostWidth: Int
        let viewportHeight: Int
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: TimelineNativeScrollViewport<Content>
        var host: UIHostingController<AnyView>?
        var lastHostedContentKey: HostedContentKey?
        // updateUIView 実行中(=SwiftUIの画面更新中)は true。
        // この間の状態書き込みは次のタイミングへ遅らせる。
        var isPerformingViewUpdate = false
        private var lastRenderOffset: CGFloat = -.greatestFiniteMagnitude
        private var lastViewportWidth: CGFloat = -.greatestFiniteMagnitude

        init(_ parent: TimelineNativeScrollViewport<Content>) {
            self.parent = parent
        }

        func updateHostedFrame(in scrollView: UIScrollView) {
            let contentWidth = max(1, parent.contentWidth)
            let hostWidth = min(max(1, parent.hostWidth), contentWidth)
            let hostOrigin = min(max(0, parent.hostOrigin), max(0, contentWidth - hostWidth))
            scrollView.contentSize = CGSize(width: contentWidth, height: parent.viewportHeight)
            host?.view.frame = CGRect(
                x: hostOrigin,
                y: 0,
                width: hostWidth,
                height: parent.viewportHeight
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let clampedOffset = clampedContentOffset(in: scrollView)
            if abs(scrollView.contentOffset.x - clampedOffset) > 0.5 {
                scrollView.setContentOffset(CGPoint(x: clampedOffset, y: scrollView.contentOffset.y), animated: false)
            }
            writeScrollOffset(from: scrollView)
            reportRenderWindow(scrollView, force: false)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            writeScrollOffset(from: scrollView)
            if !decelerate {
                reportRenderWindow(scrollView, force: true)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            writeScrollOffset(from: scrollView)
            reportRenderWindow(scrollView, force: true)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            writeScrollOffset(from: scrollView)
            reportRenderWindow(scrollView, force: true)
        }

        // SwiftUIの画面更新中なら、スクロール位置の反映を次のタイミングへ遅らせる
        private func writeScrollOffset(from scrollView: UIScrollView) {
            if isPerformingViewUpdate {
                DispatchQueue.main.async { [weak self, weak scrollView] in
                    guard let self, let scrollView else { return }
                    self.parent.scrollOffset = self.clampedContentOffset(in: scrollView)
                }
            } else {
                parent.scrollOffset = clampedContentOffset(in: scrollView)
            }
        }

        func reportViewport(_ scrollView: UIScrollView) {
            let frame = scrollView.convert(scrollView.bounds, to: nil)
            parent.onViewportFrameChange(frame)
        }

        func reportRenderWindow(_ scrollView: UIScrollView, force: Bool) {
            // このコールバックの先でも SwiftUI の状態を書き換えるので、
            // 画面更新中に呼ばれた場合は次のタイミングへ遅らせる
            guard !isPerformingViewUpdate else {
                DispatchQueue.main.async { [weak self, weak scrollView] in
                    guard let self, let scrollView else { return }
                    self.reportRenderWindow(scrollView, force: force)
                }
                return
            }
            let viewportWidth = max(0, scrollView.bounds.width)
            guard viewportWidth > 0 else { return }
            let renderOffset = bucketedOffset(scrollView.contentOffset.x)
            guard force
                    || abs(renderOffset - lastRenderOffset) >= 0.5
                    || abs(viewportWidth - lastViewportWidth) >= 0.5 else {
                return
            }
            lastRenderOffset = renderOffset
            lastViewportWidth = viewportWidth
            parent.onRenderFrameChange(renderOffset, viewportWidth)
        }

        private func bucketedOffset(_ offset: CGFloat) -> CGFloat {
            (max(0, offset) / parent.renderBucketWidth).rounded(.down) * parent.renderBucketWidth
        }

        private func clampedContentOffset(in scrollView: UIScrollView) -> CGFloat {
            min(max(0, scrollView.contentOffset.x), max(0, parent.contentWidth - scrollView.bounds.width))
        }
    }
}

private struct TimelineDisabledPattern: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 8
            var x = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(Color.white.opacity(0.07)), lineWidth: 1)
        }
    }
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

private struct TimelineRenderEvent: Identifiable, Equatable {
    let event: StatEvent
    let startSeconds: Int
    let endSeconds: Int
    let durationSeconds: Int
    let isDuration: Bool
    let title: String
    let pointDetail: String?
    let isFailed: Bool

    var id: UUID { event.id }

    static func == (lhs: TimelineRenderEvent, rhs: TimelineRenderEvent) -> Bool {
        lhs.id == rhs.id
            && lhs.startSeconds == rhs.startSeconds
            && lhs.endSeconds == rhs.endSeconds
            && lhs.durationSeconds == rhs.durationSeconds
            && lhs.isDuration == rhs.isDuration
            && lhs.title == rhs.title
            && lhs.pointDetail == rhs.pointDetail
            && lhs.isFailed == rhs.isFailed
    }
}

private struct TimelineVideoClip: Identifiable, Equatable {
    let fileName: String
    let index: Int
    let startSeconds: Double
    let durationSeconds: Double

    var id: String { fileName }
    var endSeconds: Double { startSeconds + durationSeconds }
}

private struct TimelineRenderWindowKey: Hashable {
    let presentationVersion: Int
    let renderOffset: Int
    let viewportWidth: Int
    let contentWidth: Int
    let maxSeconds: Int
}

private struct TimelineViewportContentIdentity: Hashable {
    let kind: String
    let renderWindowKey: TimelineRenderWindowKey
    var selectedEventID: UUID?
    var autoScrollPixels = 0
    var videoClipIDs = ""
    var selectedVideoClipID: String?
}

private struct TimelineRenderWindow {
    let key: TimelineRenderWindowKey
    let ticks: [Int]
    let trackEvents: [String: [TimelineRenderEvent]]

    static var empty: TimelineRenderWindow {
        TimelineRenderWindow(
            key: TimelineRenderWindowKey(
                presentationVersion: -1,
                renderOffset: -1,
                viewportWidth: -1,
                contentWidth: -1,
                maxSeconds: -1
            ),
            ticks: [],
            trackEvents: [:]
        )
    }
}

private struct TimelinePresentationState {
    var visibleEvents: [StatEvent]
    var scoringEvents: [StatEvent]
    var scoringProgression: [UUID: (home: Int, away: Int)]
    var playerLookup: [UUID: Player]
    var trackEvents: [String: [StatEvent]]
    var trackRenderEvents: [String: [TimelineRenderEvent]]
    var trackCounts: [String: Int]
    var scoringCount: Int
    var setPieceCount: Int
    var possessionCount: Int
    var halfDurations: [Int: Int]
    var halfOffsets: [Int: Int]
    var maxSeconds: Int
    var inferredPossessionStarts: [UUID: Int]
    var timelineStartSeconds: [UUID: Int]

    static var empty: TimelinePresentationState {
        TimelinePresentationState(
            visibleEvents: [],
            scoringEvents: [],
            scoringProgression: [:],
            playerLookup: [:],
            trackEvents: [:],
            trackRenderEvents: [:],
            trackCounts: [:],
            scoringCount: 0,
            setPieceCount: 0,
            possessionCount: 0,
            halfDurations: [0: 60, 1: 60],
            halfOffsets: [0: 0, 1: 0],
            maxSeconds: 60,
            inferredPossessionStarts: [:],
            timelineStartSeconds: [:]
        )
    }

    func halfDuration(for half: Int) -> Int {
        halfDurations[half, default: 60]
    }

    func halfOffset(for half: Int) -> Int {
        halfOffsets[half, default: 0]
    }
}

private struct TimelineEventBlocksLayer: View, Equatable {
    let events: [TimelineRenderEvent]
    let maxSeconds: Int
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
    let renderOffset: CGFloat
    let positionOffset: CGFloat
    let editableStartX: CGFloat
    let editableEndX: CGFloat
    let color: Color
    let selectedEventID: UUID?
    let resizeSensitivity: CGFloat
    let resizeAutoScrollTranslation: CGFloat
    let onTap: (TimelineRenderEvent) -> Void
    let onDragChanged: (TimelineRenderEvent, CGFloat, CGPoint) -> Void
    let onDragEnded: (TimelineRenderEvent, CGFloat) -> Void
    let onDragCancelled: () -> Void
    let onResizeStartEnded: (TimelineRenderEvent, CGFloat) -> Void
    let onResizeEndEnded: (TimelineRenderEvent, CGFloat) -> Void
    let onResizeDragChanged: (TimelineResizeEdge, CGFloat, CGPoint) -> Void
    let onResizeDragEnded: () -> Void

    static func == (lhs: TimelineEventBlocksLayer, rhs: TimelineEventBlocksLayer) -> Bool {
        lhs.events == rhs.events
            && lhs.maxSeconds == rhs.maxSeconds
            && lhs.contentWidth == rhs.contentWidth
            && lhs.viewportWidth == rhs.viewportWidth
            && lhs.renderOffset == rhs.renderOffset
            && lhs.positionOffset == rhs.positionOffset
            && lhs.editableStartX == rhs.editableStartX
            && lhs.editableEndX == rhs.editableEndX
            && lhs.selectedEventID == rhs.selectedEventID
            && lhs.resizeSensitivity == rhs.resizeSensitivity
            && lhs.autoScrollTranslationKey == rhs.autoScrollTranslationKey
    }

    private var autoScrollTranslationKey: CGFloat {
        guard let selectedEventID,
              events.contains(where: { $0.id == selectedEventID }) else {
            return 0
        }
        return resizeAutoScrollTranslation
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(events) { event in
                eventBlock(event)
            }
        }
    }

    @ViewBuilder
    private func eventBlock(_ event: TimelineRenderEvent) -> some View {
        let editableWidth = max(1, editableEndX - editableStartX)
        let rawBlockWidth = event.isDuration
            ? max(18, CGFloat(event.durationSeconds) / CGFloat(max(maxSeconds, 1)) * editableWidth)
            : CGFloat(34)
        let eventStartX = xOffset(for: event.startSeconds)
        let eventX = event.isDuration
            ? eventStartX
            : eventStartX - rawBlockWidth / 2
        let clampedX = min(max(editableStartX, eventX), max(editableStartX, editableEndX - rawBlockWidth))
        let viewportTrackWidth = viewportWidth
        let renderPadding: CGFloat = 0
        let visibleLeft = max(editableStartX, renderOffset - renderPadding)
        let visibleRight = min(editableEndX, renderOffset + viewportTrackWidth + renderPadding)
        let actualEndX = min(editableEndX, clampedX + rawBlockWidth)
        let renderedX = event.isDuration ? max(clampedX, visibleLeft) : clampedX
        let renderedEndX = event.isDuration ? min(actualEndX, visibleRight) : clampedX + rawBlockWidth
        let renderedWidth = event.isDuration ? max(18, renderedEndX - renderedX) : rawBlockWidth
        let showsStartHandle = !event.isDuration || (clampedX >= visibleLeft && clampedX <= visibleRight)
        let showsEndHandle = !event.isDuration || (actualEndX >= visibleLeft && actualEndX <= visibleRight)
        let detailText = renderedWidth > 52 ? (event.isDuration ? Self.timeText(event.durationSeconds) : event.pointDetail) : nil

        if renderedWidth > 0 && renderedX < editableEndX && renderedEndX > editableStartX {
            TimelineEventBlockView(
                title: event.title,
                detail: detailText,
                width: renderedWidth,
                minX: editableStartX,
                baseX: renderedX,
                maxX: max(editableStartX, editableEndX - renderedWidth),
                scrollOffset: positionOffset,
                color: color,
                isFailed: event.isFailed,
                isDuration: event.isDuration,
                isSelected: selectedEventID == event.id,
                showsStartHandle: showsStartHandle,
                showsEndHandle: showsEndHandle,
                resizeSensitivity: resizeSensitivity,
                resizeAutoScrollTranslation: selectedEventID == event.id ? resizeAutoScrollTranslation : 0,
                onTap: {
                    onTap(event)
                },
                onDragChanged: { translation, location in
                    onDragChanged(event, translation, location)
                },
                onDragEnded: { translation in
                    onDragEnded(event, translation)
                },
                onDragCancelled: onDragCancelled,
                onResizeStartEnded: { translation in
                    onResizeStartEnded(event, translation)
                },
                onResizeEndEnded: { translation in
                    onResizeEndEnded(event, translation)
                },
                onResizeDragChanged: onResizeDragChanged,
                onResizeDragEnded: onResizeDragEnded
            )
            .equatable()
        }
    }

    private func xOffset(for seconds: Int) -> CGFloat {
        editableStartX
            + CGFloat(min(max(0, seconds), maxSeconds)) / CGFloat(max(maxSeconds, 1))
            * max(1, editableEndX - editableStartX)
    }

    private static func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TimelineEventBlockView: View, Equatable {
    let title: String
    let detail: String?
    let width: CGFloat
    let minX: CGFloat
    let baseX: CGFloat
    let maxX: CGFloat
    let scrollOffset: CGFloat
    let color: Color
    let isFailed: Bool
    let isDuration: Bool
    let isSelected: Bool
    let showsStartHandle: Bool
    let showsEndHandle: Bool
    let resizeSensitivity: CGFloat
    let resizeAutoScrollTranslation: CGFloat
    let onTap: () -> Void
    let onDragChanged: (CGFloat, CGPoint) -> Void
    let onDragEnded: (CGFloat) -> Void
    let onDragCancelled: () -> Void
    let onResizeStartEnded: (CGFloat) -> Void
    let onResizeEndEnded: (CGFloat) -> Void
    let onResizeDragChanged: (TimelineResizeEdge, CGFloat, CGPoint) -> Void
    let onResizeDragEnded: () -> Void

    @GestureState private var dragState: DragState = .inactive
    @GestureState private var resizeState: ResizeState = .inactive

    static func == (lhs: TimelineEventBlockView, rhs: TimelineEventBlockView) -> Bool {
        lhs.title == rhs.title
            && lhs.detail == rhs.detail
            && lhs.width == rhs.width
            && lhs.minX == rhs.minX
            && lhs.baseX == rhs.baseX
            && lhs.maxX == rhs.maxX
            && lhs.scrollOffset == rhs.scrollOffset
            && lhs.isFailed == rhs.isFailed
            && lhs.isDuration == rhs.isDuration
            && lhs.isSelected == rhs.isSelected
            && lhs.showsStartHandle == rhs.showsStartHandle
            && lhs.showsEndHandle == rhs.showsEndHandle
            && lhs.resizeSensitivity == rhs.resizeSensitivity
            && lhs.autoScrollTranslationKey == rhs.autoScrollTranslationKey
    }

    private var autoScrollTranslationKey: CGFloat {
        isSelected ? resizeAutoScrollTranslation : 0
    }

    private var currentX: CGFloat {
        let autoScrollTranslation = dragState.isActive ? resizeAutoScrollTranslation : 0
        return min(max(minX, baseX + dragState.translation + autoScrollTranslation), maxX)
    }

    private var previewX: CGFloat {
        if let leftTranslation = resizeState.leftTranslation {
            return min(max(minX - baseX, resizePreviewTranslation(leftTranslation) + resizeAutoScrollTranslation), width - minimumDurationWidth)
        }
        return 0
    }

    private var previewWidth: CGFloat {
        if resizeState.leftTranslation != nil {
            return max(minimumDurationWidth, width - previewX)
        }
        if let rightTranslation = resizeState.rightTranslation {
            let timelineWidth = maxX + width
            return min(max(minimumDurationWidth, width + resizePreviewTranslation(rightTranslation) + resizeAutoScrollTranslation), timelineWidth - baseX)
        }
        return width
    }

    private var displayedX: CGFloat {
        currentX + (isResizing ? previewX : 0)
    }

    private var displayedWidth: CGFloat {
        isResizing ? previewWidth : width
    }

    private var isLifted: Bool {
        dragState.isActive
    }

    private var isResizing: Bool {
        resizeState.isActive
    }

    private var minimumDurationWidth: CGFloat {
        min(18, max(8, width))
    }

    private var outlineColor: Color {
        if isLifted || isResizing {
            return Color.white.opacity(0.92)
        }
        if isSelected {
            return Color.blue.opacity(0.95)
        }
        return isFailed ? Color.orange.opacity(0.82) : Color.white.opacity(0.18)
    }

    private var cornerRadius: CGFloat {
        3
    }

    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($dragState) { value, state, _ in
                switch value {
                case .first(true):
                    state = .pressing
                case .second(true, let drag):
                    state = .dragging(drag?.translation.width ?? 0)
                default:
                    state = .inactive
                }
            }
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                onDragChanged(drag.translation.width, drag.location)
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value else {
                    onDragCancelled()
                    return
                }
                onDragEnded(drag.translation.width)
            }
    }

    private func resizeGesture(edge: ResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($resizeState) { value, state, _ in
                guard isSelected else {
                    state = .inactive
                    return
                }
                state = .dragging(edge, value.translation.width)
            }
            .onChanged { value in
                guard isSelected else { return }
                onResizeDragChanged(edge.timelineEdge, value.translation.width, value.location)
            }
            .onEnded { value in
                guard isSelected else { return }
                switch edge {
                case .start:
                    onResizeStartEnded(value.translation.width)
                case .end:
                    onResizeEndEnded(value.translation.width)
                }
                onResizeDragEnded()
            }
    }

    var body: some View {
        Group {
            if isSelected {
                blockContent
                    .simultaneousGesture(dragGesture)
            } else {
                blockContent
            }
        }
    }

    private var blockContent: some View {
        ZStack(alignment: .leading) {
            Color.clear

            if isDuration && isSelected && (showsStartHandle || showsEndHandle) {
                HStack(spacing: 0) {
                    if showsStartHandle {
                        resizeHandle(edge: .start)
                    }
                    Spacer(minLength: 0)
                    if showsEndHandle {
                        resizeHandle(edge: .end)
                    }
                }
            }

        }
        .foregroundStyle(.white)
        .frame(width: displayedWidth, height: 28)
        .background(color.opacity(isFailed ? 0.46 : 0.82))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(outlineColor, lineWidth: (isLifted || isResizing || isSelected) ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .scaleEffect(isLifted ? 1.05 : 1.0)
        .offset(x: displayedX - scrollOffset)
        .offset(y: isLifted ? -4 : 0)
        .shadow(color: .black.opacity(isLifted ? 0.38 : 0), radius: 10, x: 0, y: 8)
        .zIndex(isLifted ? 3 : 1)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onTapGesture(perform: onTap)
    }

    private func resizeHandle(edge: ResizeEdge) -> some View {
        Circle()
            .fill(color.opacity(resizeState.edge == edge ? 1.0 : 0.94))
            .frame(width: 13, height: 13)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.86), lineWidth: 1)
            )
            .frame(width: 24, height: 28)
            .offset(x: edge == .start ? -6 : 6)
            .contentShape(Rectangle())
            .highPriorityGesture(resizeGesture(edge: edge))
    }

    private func resizePreviewTranslation(_ translation: CGFloat) -> CGFloat {
        translation * resizeSensitivity
    }

    private enum DragState: Equatable {
        case inactive
        case pressing
        case dragging(CGFloat)

        var translation: CGFloat {
            switch self {
            case .inactive, .pressing:
                return 0
            case .dragging(let translation):
                return translation
            }
        }

        var isActive: Bool {
            self != .inactive
        }
    }

    private enum ResizeEdge: Equatable {
        case start
        case end

        var timelineEdge: TimelineResizeEdge {
            switch self {
            case .start: return .start
            case .end: return .end
            }
        }
    }

    private enum ResizeState: Equatable {
        case inactive
        case dragging(ResizeEdge, CGFloat)

        var leftTranslation: CGFloat? {
            switch self {
            case .dragging(.start, let translation):
                return translation
            default:
                return nil
            }
        }

        var rightTranslation: CGFloat? {
            switch self {
            case .dragging(.end, let translation):
                return translation
            default:
                return nil
            }
        }

        var edge: ResizeEdge? {
            switch self {
            case .inactive:
                return nil
            case .dragging(let edge, _):
                return edge
            }
        }

        var isActive: Bool {
            self != .inactive
        }
    }
}

private struct TimelineEventDraft {
    var category: TimelineEventCategory
    var half: Int
    var seconds: Int
    var durationSeconds: Int
    var teamSide: TimelineTeamSide
    var isSuccessful: Bool
    var playerID: UUID?
}

private struct TimelineDeletionCandidate: Identifiable {
    let id: UUID
    let title: String
}

private enum TimelineTeamSide: String, CaseIterable, Identifiable {
    case home
    case away

    var id: String { rawValue }
}

private struct TimelineEventAddSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialCategory: TimelineEventCategory
    let initialHalf: Int
    let homeTeamName: String
    let awayTeamName: String
    let homePlayers: [Player]
    let awayPlayers: [Player]
    let onAdd: (TimelineEventDraft) -> Void

    @State private var selectedCategory: TimelineEventCategory
    @State private var selectedHalf: Int
    @State private var eventSeconds = 0
    @State private var durationSeconds = 30
    @State private var selectedTeamSide: TimelineTeamSide = .home
    @State private var isSuccessful = true
    @State private var selectedPlayerID: UUID?

    init(
        initialCategory: TimelineEventCategory = .tryScore,
        initialHalf: Int,
        homeTeamName: String,
        awayTeamName: String,
        homePlayers: [Player],
        awayPlayers: [Player],
        onAdd: @escaping (TimelineEventDraft) -> Void
    ) {
        self.initialCategory = initialCategory
        self.initialHalf = initialHalf
        self.homeTeamName = homeTeamName
        self.awayTeamName = awayTeamName
        self.homePlayers = homePlayers
        self.awayPlayers = awayPlayers
        self.onAdd = onAdd
        _selectedCategory = State(initialValue: initialCategory)
        _selectedHalf = State(initialValue: initialHalf)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(Color.secondary.opacity(0.32))
                    .frame(width: 72, height: 5)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("イベント追加")
                            .font(.title2.weight(.black))
                        Text(selectedCategory.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(selectedCategory.color)
                    }

                    Spacer()

                    Button("閉じる") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.blue)
                }

                section("種類") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(TimelineEventCategory.allCases) { category in
                            categoryButton(category)
                        }
                    }
                }

                section("前後半") {
                    segmentedControl([
                        (title: "前半", isSelected: selectedHalf == 0, action: { selectedHalf = 0 }),
                        (title: "後半", isSelected: selectedHalf == 1, action: { selectedHalf = 1 })
                    ])
                }

                if selectedCategory.needsTeamSelection {
                    section("チーム") {
                        segmentedControl([
                            (title: "HOME", isSelected: selectedTeamSide == .home, action: {
                                selectedTeamSide = .home
                                selectedPlayerID = nil
                            }),
                            (title: "AWAY", isSelected: selectedTeamSide == .away, action: {
                                selectedTeamSide = .away
                                selectedPlayerID = nil
                            })
                        ])
                        Text(selectedTeamSide == .home ? homeTeamName : awayTeamName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                if selectedCategory.allowsOutcomeSelection {
                    section("結果") {
                        segmentedControl([
                            (title: "成功", isSelected: isSuccessful, action: { isSuccessful = true }),
                            (title: "失敗", isSelected: !isSuccessful, action: { isSuccessful = false })
                        ])
                    }
                }

                if selectedCategory.allowsPlayerSelection {
                    section("選手") {
                        playerMenu
                    }
                }

                secondsEditor(title: selectedCategory.isDuration ? "開始" : "時刻", value: eventSeconds) { newValue in
                    eventSeconds = max(0, newValue)
                }

                if selectedCategory.isDuration {
                    secondsEditor(title: "長さ", value: durationSeconds) { newValue in
                        durationSeconds = max(1, newValue)
                    }
                }

                Button {
                    onAdd(
                        TimelineEventDraft(
                            category: selectedCategory,
                            half: selectedHalf,
                            seconds: eventSeconds,
                            durationSeconds: durationSeconds,
                            teamSide: selectedTeamSide,
                            isSuccessful: isSuccessful,
                            playerID: selectedCategory.allowsPlayerSelection ? selectedPlayerID : nil
                        )
                    )
                    dismiss()
                } label: {
                    Label("追加", systemImage: "plus.circle.fill")
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

    private var activePlayers: [Player] {
        selectedTeamSide == .home ? homePlayers : awayPlayers
    }

    private var selectedPlayerName: String {
        guard let selectedPlayerID,
              let player = activePlayers.first(where: { $0.id == selectedPlayerID }) else {
            return "選手なし"
        }
        return playerDisplayName(player)
    }

    private var playerMenu: some View {
        Menu {
            Button("選手なし") {
                selectedPlayerID = nil
            }
            ForEach(activePlayers, id: \.id) { player in
                Button(playerDisplayName(player)) {
                    selectedPlayerID = player.id
                }
            }
        } label: {
            HStack {
                Text(selectedPlayerName)
                    .font(.headline.weight(.bold))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.black))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func categoryButton(_ category: TimelineEventCategory) -> some View {
        Button {
            selectedCategory = category
            if !category.allowsOutcomeSelection {
                isSuccessful = true
            }
            if !category.allowsPlayerSelection {
                selectedPlayerID = nil
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.systemImage)
                    .font(.caption.weight(.black))
                    .frame(width: 18)
                Text(category.shortTitle)
                    .font(.caption.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selectedCategory == category ? .white : category.color)
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background((selectedCategory == category ? category.color : category.color.opacity(0.14)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func segmentedControl(_ items: [(title: String, isSelected: Bool, action: () -> Void)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button(action: item.action) {
                    Text(item.title)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(item.isSelected ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if item.isSelected {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func secondsEditor(title: String, value: Int, onChange: @escaping (Int) -> Void) -> some View {
        section(title) {
            HStack {
                Text(Self.timeText(value))
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                Spacer()
            }

            HStack(spacing: 8) {
                stepButton("-1分", value: value, delta: -60, minimum: title == "長さ" ? 1 : 0, onChange: onChange)
                stepButton("-10秒", value: value, delta: -10, minimum: title == "長さ" ? 1 : 0, onChange: onChange)
                stepButton("+10秒", value: value, delta: 10, minimum: title == "長さ" ? 1 : 0, onChange: onChange)
                stepButton("+1分", value: value, delta: 60, minimum: title == "長さ" ? 1 : 0, onChange: onChange)
            }
        }
    }

    private func stepButton(
        _ title: String,
        value: Int,
        delta: Int,
        minimum: Int,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        Button {
            onChange(max(minimum, value + delta))
        } label: {
            Text(title)
                .font(.caption.weight(.black).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(delta < 0 ? Color.orange : Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(delta < 0 && value <= minimum)
        .opacity(delta < 0 && value <= minimum ? 0.45 : 1)
    }

    private func playerDisplayName(_ player: Player) -> String {
        if let name = player.name, !name.isEmpty {
            return "#\(player.number) \(name)"
        }
        return "#\(player.number)"
    }

    private static func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
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

private struct EventTimeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let event: StatEvent
    let editorTitle: String
    let eventTitle: String
    let eventSubtitle: String
    let halfText: String
    let impactText: String
    let impactColor: Color
    let accent: Color
    let onAdjust: (Int) -> Int
    let onDelete: () -> Void

    @State private var displayedSeconds: Int

    init(
        event: StatEvent,
        editorTitle: String,
        eventTitle: String,
        eventSubtitle: String,
        halfText: String,
        impactText: String,
        impactColor: Color,
        accent: Color,
        onAdjust: @escaping (Int) -> Int,
        onDelete: @escaping () -> Void
    ) {
        self.event = event
        self.editorTitle = editorTitle
        self.eventTitle = eventTitle
        self.eventSubtitle = eventSubtitle
        self.halfText = halfText
        self.impactText = impactText
        self.impactColor = impactColor
        self.accent = accent
        self.onAdjust = onAdjust
        self.onDelete = onDelete
        _displayedSeconds = State(initialValue: event.seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 72, height: 5)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(editorTitle)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(eventTitle)
                        .font(.title2.weight(.black))
                    Text(eventSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button("完了") {
                    dismiss()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.blue)
            }

            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Text(halfText)
                        .font(.headline.weight(.black))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.16))
                        .clipShape(Capsule())

                    Text(impactText)
                        .font(.headline.weight(.black).monospacedDigit())
                        .foregroundStyle(impactColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(impactColor.opacity(0.14))
                        .clipShape(Capsule())
                }

                Spacer()

                Text(Self.timeText(displayedSeconds))
                    .font(.system(size: 42, weight: .black, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 10) {
                adjustButton("-10秒", delta: -10)
                adjustButton("-1秒", delta: -1)
                adjustButton("+1秒", delta: 1)
                adjustButton("+10秒", delta: 10)
            }

            HStack(spacing: 10) {
                adjustButton("-1分", delta: -60)
                adjustButton("-30秒", delta: -30)
                adjustButton("+30秒", delta: 30)
                adjustButton("+1分", delta: 60)
            }

            HStack(spacing: 10) {
                adjustButton("-5分", delta: -300)
                adjustButton("+5分", delta: 300)
            }

            Text(event.category == "possession" ? "区間ブロックは横ドラッグで開始位置、ボタンで長さを調整できます。" : "時刻を変更すると、一覧と得点タイムラインの並び順が再計算されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                dismiss()
                onDelete()
            } label: {
                Label("イベントを削除", systemImage: "trash.fill")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private static func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func adjustButton(_ title: String, delta: Int) -> some View {
        Button {
            displayedSeconds = onAdjust(delta)
        } label: {
            Text(title)
                .font(.headline.weight(.black).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(delta < 0 ? Color.orange : Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(delta < 0 && displayedSeconds == 0)
        .opacity(delta < 0 && displayedSeconds == 0 ? 0.45 : 1)
    }
}

private struct TimelineTrackDefinition: Identifiable {
    var id: String { title }
    let title: String
    let systemImage: String
    let color: Color
    let matches: (StatEvent, Match) -> Bool
}

private enum TimelineResizeEdge: Equatable {
    case start
    case end
}

private enum TimelineEventCategory: CaseIterable, Identifiable {
    case homePossession
    case awayPossession
    case bip
    case tryScore
    case conversion
    case penaltyGoal
    case dropGoal
    case lineout
    case scrum

    var id: String { storageCategory + shortTitle }

    var storageCategory: String {
        switch self {
        case .homePossession, .awayPossession, .bip: return "possession"
        case .tryScore: return "try"
        case .conversion: return "conversion"
        case .penaltyGoal: return "penalty_goal"
        case .dropGoal: return "drop_goal"
        case .lineout: return "lineout"
        case .scrum: return "scrum"
        }
    }

    var systemImage: String {
        switch self {
        case .homePossession: return "house.fill"
        case .awayPossession: return "a.circle.fill"
        case .bip: return "clock.fill"
        case .tryScore: return "rugbyball.fill"
        case .conversion: return "figure.rugby"
        case .penaltyGoal: return "p.circle.fill"
        case .dropGoal: return "d.circle.fill"
        case .lineout: return "figure.strengthtraining.traditional"
        case .scrum: return "person.3.fill"
        }
    }

    var isDuration: Bool {
        switch self {
        case .homePossession, .awayPossession, .bip: return true
        default: return false
        }
    }

    var needsTeamSelection: Bool {
        switch self {
        case .tryScore, .conversion, .penaltyGoal, .dropGoal, .lineout, .scrum:
            return true
        case .homePossession, .awayPossession, .bip:
            return false
        }
    }

    var allowsOutcomeSelection: Bool {
        switch self {
        case .conversion, .penaltyGoal, .dropGoal, .lineout, .scrum:
            return true
        case .homePossession, .awayPossession, .bip, .tryScore:
            return false
        }
    }

    var allowsPlayerSelection: Bool {
        switch self {
        case .tryScore, .conversion, .penaltyGoal, .dropGoal:
            return true
        case .homePossession, .awayPossession, .bip, .lineout, .scrum:
            return false
        }
    }

    var title: String {
        switch self {
        case .homePossession: return "HOME"
        case .awayPossession: return "AWAY"
        case .bip: return "BIP"
        case .tryScore: return "トライ"
        case .conversion: return "コンバージョン"
        case .penaltyGoal: return "PG"
        case .dropGoal: return "DG"
        case .lineout: return "ラインアウト"
        case .scrum: return "スクラム"
        }
    }

    var shortTitle: String {
        switch self {
        case .homePossession: return "HOME"
        case .awayPossession: return "AWAY"
        case .bip: return "BIP"
        case .tryScore: return "TRY"
        case .conversion: return "CONV"
        case .penaltyGoal: return "PG"
        case .dropGoal: return "DG"
        case .lineout: return "LO"
        case .scrum: return "SCR"
        }
    }

    var detailFallback: String {
        switch self {
        case .homePossession, .awayPossession: return "ポゼッション区間"
        case .bip: return "ボールインプレー区間"
        case .lineout, .scrum: return "選手なし"
        default: return "得点者未設定"
        }
    }

    var color: Color {
        switch self {
        case .homePossession: return .timelineHome
        case .awayPossession: return .timelineAway
        case .bip: return .timelineBIP
        case .tryScore: return .timelineTry
        case .conversion: return .timelineConversion
        case .penaltyGoal, .dropGoal: return .timelineKick
        case .lineout: return .timelineLineout
        case .scrum: return .timelineScrum
        }
    }
}

private extension Color {
    static var timelineHome: Color { Color(red: 0.02, green: 0.32, blue: 0.95) }
    static var timelineAway: Color { Color(red: 0.98, green: 0.12, blue: 0.18) }
    static var timelineBIP: Color { Color(red: 0.35, green: 0.15, blue: 0.88) }
    static var timelineTry: Color { Color(red: 0.22, green: 0.70, blue: 0.24) }
    static var timelineConversion: Color { Color(red: 0.00, green: 0.58, blue: 0.66) }
    static var timelineKick: Color { Color(red: 0.93, green: 0.72, blue: 0.13) }
    static var timelineLineout: Color { Color(red: 0.05, green: 0.68, blue: 0.70) }
    static var timelineScrum: Color { Color(red: 0.91, green: 0.35, blue: 0.05) }
    static var timelineVideo: Color { Color(red: 0.58, green: 0.38, blue: 0.96) }
    static var timelineMatch: Color { Color(red: 0.12, green: 0.72, blue: 0.56) }
}

private extension View {
    func timelineCard(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.075))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color(red: 0.04, green: 0.08, blue: 0.13).opacity(0.82))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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
