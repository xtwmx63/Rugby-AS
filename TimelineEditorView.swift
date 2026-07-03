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
    @State private var videoEndObserver: NSObjectProtocol?
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
