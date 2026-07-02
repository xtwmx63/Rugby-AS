//
//  TimelineEditorView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/29.
//

import Combine
import SwiftData
import SwiftUI
import UIKit

// 再生ヘッドの時刻とスクロール位置はスクロール中に毎フレーム変わる。
// これを画面全体の状態(@State)に置くと毎フレーム画面全体を再計算して
// カクつくため、この小さな箱に隔離し、時刻ラベルなど必要な部品だけが購読する。
@MainActor
private final class TimelinePlayheadState: ObservableObject {
    @Published var second: Double = 0

    // スクロールの生の位置。描画には使わないので @Published にしない。
    var liveScrollOffset: CGFloat = 0

    // 再生ヘッド起点で動かしたスクロールの目標位置。
    // ここと一致している間は「ユーザーが指で動かした」扱いにしない。
    var programmaticTargetOffset: CGFloat?
}

// 再生ヘッド時刻の表示形式(分:秒.1/10秒)
private func timelinePlayheadTimeText(_ seconds: Double) -> String {
    let totalTenths = Int((max(0, seconds) * 10).rounded())
    let minutes = totalTenths / 600
    let wholeSeconds = (totalTenths / 10) % 60
    let tenths = totalTenths % 10
    return String(format: "%02d:%02d.%d", minutes, wholeSeconds, tenths)
}

struct TimelineEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let match: Match

    @State private var selectedScope: TimelineScope = .first
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
    @State private var isTimelineOverviewMode = true
    @State private var playhead = TimelinePlayheadState()
    @State private var didSetInitialPlayheadPosition = false

    private let minimumTimelineZoom: CGFloat = 0.035
    private let maximumTimelineZoom: CGFloat = 10.0
    private let resizeSensitivity: CGFloat = 1.35
    private let timelineAutoScrollEdgeInset: CGFloat = 76
    private let timelineAutoScrollStep: CGFloat = 34
    private let timelineTrackLabelWidth: CGFloat = 96
    private let timelineRulerHeight: CGFloat = 44
    private let timelineTrackRowHeight: CGFloat = 42
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
        .onChange(of: selectedScope) { _, _ in
            didSetInitialPlayheadPosition = false
            stopTimelinePlayback()
            rebuildTimelinePresentation()
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
        .onDisappear {
            pendingTimelineSaveTask?.cancel()
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

                TimelineShareButton(playhead: playhead, sharePrefix: timelineSharePrefix)
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private var timelineSharePrefix: String {
        "\(teamName(for: match.homeTeamID)) \(score(for: match.homeTeamID)) - \(score(for: match.awayTeamID)) \(teamName(for: match.awayTeamID))"
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
                timelineRulerHeight + timelineTrackRowHeight * 5 + 1
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
        RugbyVideoPreview()
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.26), radius: 16, x: 0, y: 10)
    }

    private func playbackControls(maxSeconds: Int) -> some View {
        ZStack {
            HStack(spacing: 8) {
                TimelinePlayheadTimeLabel(playhead: playhead, maxSeconds: maxSeconds)

                Spacer(minLength: 46)

                HStack(spacing: 10) {
                    timelineRoundControl(systemName: "arrow.uturn.backward") {
                        nudgePlayhead(by: -10, maxSeconds: maxSeconds)
                    }

                    timelineRoundControl(systemName: "arrow.uturn.forward") {
                        nudgePlayhead(by: 10, maxSeconds: maxSeconds)
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
        let rowsHeight = CGFloat(trackDefinitions.count) * timelineTrackRowHeight

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
                contentVersion: timelineRulerContentVersion(contentWidth: contentWidth, renderedFrame: renderedFrame),
                scrollOffset: $timelineScrollOffset,
                onLiveScroll: { offset in
                    syncPlayhead(fromLiveOffset: offset)
                },
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
                contentVersion: timelineTracksContentVersion(contentWidth: contentWidth, renderedFrame: renderedFrame),
                scrollOffset: $timelineScrollOffset,
                onLiveScroll: { offset in
                    syncPlayhead(fromLiveOffset: offset)
                },
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
            ForEach(trackDefinitions) { track in
                HStack(spacing: 8) {
                    Image(systemName: track.systemImage)
                        .font(.title3.weight(.black))
                        .foregroundStyle(track.color)
                        .frame(width: 24)

                    Text(trackDisplayTitle(track))
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
        }
        .frame(width: timelineTrackLabelWidth, height: rowsHeight, alignment: .topLeading)
        .background(Color.black.opacity(0.001))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
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
                    contentVersion: timelineTracksContentVersion(contentWidth: contentWidth, renderedFrame: renderedFrame),
                    scrollOffset: $timelineScrollOffset,
                    onLiveScroll: { offset in
                        syncPlayhead(fromLiveOffset: offset)
                    },
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
                halfDivider(maxSeconds: maxSeconds, contentWidth: contentWidth, scrollOffset: contentOrigin)
            }
        }
        .frame(width: windowWidth, height: 44, alignment: .leading)
        .clipped()
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
        .frame(width: windowWidth, height: 44, alignment: .leading)
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

    // スクロール中の作り直しを避けるため「中身が変わったか」を1つの数値で表す。
    // この値が変わったときだけ TimelineNativeScrollViewport が中身を更新する。
    // ズーム中は contentWidth が毎フレーム変わるので、必ず現在値を含める
    // (含めないとズームしても描画が古い縮尺のまま止まる)。
    private func timelineRulerContentVersion(
        contentWidth: CGFloat,
        renderedFrame: (origin: CGFloat, width: CGFloat)
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(timelineRenderWindow.key)
        hasher.combine(Int((contentWidth * 2).rounded()))
        hasher.combine(Int((renderedFrame.origin * 2).rounded()))
        hasher.combine(Int((renderedFrame.width * 2).rounded()))
        return hasher.finalize()
    }

    private func timelineTracksContentVersion(
        contentWidth: CGFloat,
        renderedFrame: (origin: CGFloat, width: CGFloat)
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(timelineRulerContentVersion(contentWidth: contentWidth, renderedFrame: renderedFrame))
        hasher.combine(selectedTimelineEventID)
        hasher.combine(timelineAutoScrollAccumulatedPixels)
        return hasher.finalize()
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
        let rawWidth = max(18, CGFloat(duration) / CGFloat(max(maxSeconds, 1)) * contentWidth)
        let rawEndX = rawX + rawWidth
        let renderPadding: CGFloat = 0
        let visibleLeft = max(0, scrollOffset - renderPadding)
        let visibleRight = min(contentWidth, scrollOffset + viewportWidth + renderPadding)
        let renderedX = max(rawX, visibleLeft)
        let renderedEndX = min(rawEndX, visibleRight)
        let renderedWidth = max(18, renderedEndX - renderedX)
        let label = half == 0 ? "前半" : "後半"

        return Group {
            if rawEndX >= visibleLeft && rawX <= visibleRight {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.caption2.weight(.black))
                    Text(timeText(duration))
                        .font(.caption2.weight(.bold).monospacedDigit())
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

        event.startSeconds = timelineLocalSeconds(from: start, half: event.half)
        event.seconds = max(1, end - start)

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

    // 1ステップの移動量。間隔を85ms→33msに縮めた分だけ小さくして、
    // 移動速度は変えずに動きだけ滑らかにする。
    private func timelineAutoScrollRepeatingStep(for power: CGFloat) -> CGFloat {
        timelineAutoScrollStep * (0.08 + power * 2.45) * (33.0 / 85.0)
    }

    private func startTimelineAutoScroll(direction: Int, maxSeconds: Int, intensity: CGFloat) {
        let shouldUpdateState = timelineAutoScrollDirection != direction
            || timelineAutoScrollMaxSeconds != maxSeconds
            || abs(timelineAutoScrollIntensity - intensity) > 0.035

        if shouldUpdateState {
            timelineAutoScrollDirection = direction
            timelineAutoScrollMaxSeconds = maxSeconds
            timelineAutoScrollIntensity = intensity
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
                try? await Task.sleep(for: .milliseconds(33))
            }
            timelineAutoScrollTask = nil
        }
    }

    private func advanceTimelineAutoScroll(direction: Int, maxSeconds: Int, step: CGFloat) {
        guard direction != 0 else { return }
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)
        let previousOffset = playhead.liveScrollOffset
        let nextOffset = clampedTimelineScrollOffset(
            previousOffset + CGFloat(direction) * step,
            contentWidth: contentWidth,
            viewportWidth: timelineViewportFrame.width
        )
        playhead.liveScrollOffset = nextOffset
        timelineScrollOffset = nextOffset

        let pixelDelta = nextOffset - previousOffset
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
        let playbackStartSecond = min(playhead.second, Double(maxSeconds))
        let playbackStartDate = Date()
        timelinePlaybackTask = Task { @MainActor in
            while !Task.isCancelled {
                let currentMaxSeconds = timelinePresentation.maxSeconds
                let elapsedSeconds = Date().timeIntervalSince(playbackStartDate)
                let currentSecond = min(playbackStartSecond + elapsedSeconds, Double(currentMaxSeconds))
                scrollToTimelineSecond(currentSecond, maxSeconds: currentMaxSeconds)

                guard currentSecond < Double(currentMaxSeconds) else {
                    stopTimelinePlayback()
                    break
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopTimelinePlayback() {
        timelinePlaybackTask?.cancel()
        timelinePlaybackTask = nil
        isTimelinePlaying = false
    }

    private func updateTimelineAvailableViewportWidth(_ width: CGFloat) {
        let viewportWidth = max(220, width - 16 - timelineTrackLabelWidth)
        guard abs(timelineAvailableViewportWidth - viewportWidth) > 0.5 else { return }
        timelineAvailableViewportWidth = viewportWidth
        isTimelineOverviewMode = true
        updateTimelineScrollOffsetFromPlayhead(0)
        playhead.second = 0
        refreshTimelineRenderWindow(
            for: timelinePresentation,
            version: timelinePresentationVersion
        )
    }

    private func nudgePlayhead(by delta: Double, maxSeconds: Int) {
        stopTimelinePlayback()
        scrollToTimelineSecond(playhead.second + delta, maxSeconds: maxSeconds)
    }

    private func scrollToTimelineSecond(_ second: Int, maxSeconds: Int? = nil) {
        scrollToTimelineSecond(Double(second), maxSeconds: maxSeconds)
    }

    private func scrollToTimelineSecond(_ second: Double, maxSeconds: Int? = nil) {
        let maxSeconds = maxSeconds ?? timelinePresentation.maxSeconds
        let clampedSecond = min(max(0, second), Double(maxSeconds))
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)
        let viewportWidth = max(timelineRenderedViewportWidth, timelineViewportFrame.width)
        let targetX = xOffset(for: clampedSecond, maxSeconds: maxSeconds, contentWidth: contentWidth)

        playhead.second = clampedSecond
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
        playhead.programmaticTargetOffset = offset
        playhead.liveScrollOffset = offset
        timelineScrollOffset = offset
    }

    // スクロールビューが動いたときに再生ヘッドの時刻を追従させる。
    // 再生ヘッド起点で動かしたスクロールが返ってきただけの場合は何もしない
    // (時刻がスクロール位置から逆算されて微妙にズレるのを防ぐ)。
    private func syncPlayhead(fromLiveOffset offset: CGFloat) {
        playhead.liveScrollOffset = offset

        if let target = playhead.programmaticTargetOffset {
            if abs(offset - target) <= 1.0 {
                return
            }
            playhead.programmaticTargetOffset = nil
        }

        let maxSeconds = timelinePresentation.maxSeconds
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)
        let viewportWidth = max(timelineRenderedViewportWidth, timelineViewportFrame.width)
        guard viewportWidth > 0 else { return }

        let markerX = min(contentWidth, max(0, offset + viewportWidth / 2))
        let second = Double(timelineSecond(forContentX: markerX, maxSeconds: maxSeconds, contentWidth: contentWidth))
        playhead.second = min(max(0, second), Double(maxSeconds))
    }

    private func positionInitialPlayheadIfNeeded(maxSeconds: Int, contentWidth: CGFloat) {
        guard !didSetInitialPlayheadPosition else { return }
        let viewportWidth = max(timelineRenderedViewportWidth, timelineViewportFrame.width)
        guard viewportWidth > 0 else { return }

        didSetInitialPlayheadPosition = true
        isTimelineOverviewMode = true
        playhead.second = 0
        updateTimelineScrollOffsetFromPlayhead(0)
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
                keepPlayheadCenteredAfterZoom()
            }
            .onEnded { value in
                setTimelineZoom(baseTimelineZoom * value)
            }
    }

    private func setTimelineZoom(_ zoom: CGFloat) {
        isTimelineOverviewMode = zoom <= minimumTimelineZoom
        timelineZoom = clampedTimelineZoom(zoom)
        baseTimelineZoom = timelineZoom
        keepPlayheadCenteredAfterZoom()
    }

    // ズームで横幅が変わっても、再生ヘッド位置の中身が画面中央から
    // 動かないようにスクロール位置を取り直す(動画編集アプリと同じ挙動)。
    private func keepPlayheadCenteredAfterZoom() {
        scrollToTimelineSecond(playhead.second)
    }

    private func clampedTimelineZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumTimelineZoom, max(minimumTimelineZoom, zoom))
    }

    private func clampedTimelineSecond(for event: StatEvent, proposedSecond: Int) -> Int {
        let halfStart = halfTimelineOffset(for: event.half)
        let halfEnd = halfStart + timelinePresentation.halfDuration(for: event.half)
        let latestStart = event.category == "possession"
            ? max(halfStart, halfEnd - max(0, event.seconds))
            : halfEnd
        return min(max(halfStart, proposedSecond), latestStart)
    }

    private func timelineLocalSeconds(from timelineSecond: Int, half: Int) -> Int {
        max(0, timelineSecond - halfTimelineOffset(for: half))
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

    private func halfDivider(maxSeconds: Int, contentWidth: CGFloat, scrollOffset: CGFloat) -> some View {
        Rectangle()
            .fill(Color.blue.opacity(0.75))
            .frame(width: 2, height: 34)
            .offset(x: xOffset(for: halfTimelineOffset(for: 1), maxSeconds: maxSeconds, contentWidth: contentWidth) - scrollOffset)
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
            ? defaultHalfTimelineSeconds * 2
            : defaultHalfTimelineSeconds
        let roundedMaxSeconds = Int(ceil(Double(max(rawMaxSeconds, baselineSeconds)) / 60.0)) * 60
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
                makeTimelineRenderEvent(
                    from: event,
                    startSeconds: timelineStartSeconds[event.id] ?? calculatedTimelineStartSecond(
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

            events = try modelContext.fetch(eventDescriptor)
            players = try modelContext.fetch(playerDescriptor)
            teams = try modelContext.fetch(FetchDescriptor<Team>())
            setTimelineZoom(minimumTimelineZoom)
            didSetInitialPlayheadPosition = false
            rebuildTimelinePresentation()
            didLoad = true
        } catch {
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
            .map(\.seconds)
            .max() ?? 0
        let maxStoredPossessionEnd = halfEvents
            .filter { $0.category == "possession" }
            .compactMap { event in
                event.startSeconds.map { $0 + max(0, event.seconds) }
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
        return max(maxPointSeconds, maxStoredPossessionEnd, homeAwayDuration, bipDuration, defaultHalfTimelineSeconds)
    }

    private func calculatedTimelineStartSecond(
        for event: StatEvent,
        halfOffsets: [Int: Int],
        inferredPossessionStarts: [UUID: Int]
    ) -> Int {
        let halfOffset = halfOffsets[event.half, default: 0]
        if event.category == "possession" {
            return halfOffset + (event.startSeconds ?? inferredPossessionStarts[event.id] ?? 0)
        }
        return halfOffset + event.seconds
    }

    private func makeTimelineRenderEvent(from event: StatEvent, startSeconds: Int) -> TimelineRenderEvent {
        let isDuration = event.category == "possession"
        return TimelineRenderEvent(
            event: event,
            startSeconds: startSeconds,
            endSeconds: isDuration ? startSeconds + max(1, event.seconds) : startSeconds,
            durationSeconds: max(1, event.seconds),
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

// 再生ヘッド時刻の表示。この部品だけが毎フレームの時刻更新を受け取る。
private struct TimelinePlayheadTimeLabel: View {
    @ObservedObject var playhead: TimelinePlayheadState
    let maxSeconds: Int

    var body: some View {
        HStack(spacing: 3) {
            Text(timelinePlayheadTimeText(min(playhead.second, Double(maxSeconds))))
                .foregroundStyle(Color.timelineHome)
            Text("/ \(String(format: "%02d:%02d", maxSeconds / 60, maxSeconds % 60))")
                .foregroundStyle(.white.opacity(0.52))
        }
        .font(.system(size: 18, weight: .bold).monospacedDigit())
    }
}

private struct TimelineShareButton: View {
    @ObservedObject var playhead: TimelinePlayheadState
    let sharePrefix: String

    var body: some View {
        ShareLink(item: "\(sharePrefix) / \(timelinePlayheadTimeText(playhead.second))") {
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

private struct TimelineNativeScrollViewport<Content: View>: UIViewRepresentable {
    let contentWidth: CGFloat
    let viewportHeight: CGFloat
    let renderBucketWidth: CGFloat
    let hostOrigin: CGFloat
    let hostWidth: CGFloat
    let contentVersion: Int
    @Binding var scrollOffset: CGFloat
    let onLiveScroll: (CGFloat) -> Void
    let onViewportFrameChange: (CGRect) -> Void
    let onRenderFrameChange: (CGFloat, CGFloat) -> Void
    let content: () -> Content

    init(
        contentWidth: CGFloat,
        viewportHeight: CGFloat,
        renderBucketWidth: CGFloat = 360,
        hostOrigin: CGFloat,
        hostWidth: CGFloat,
        contentVersion: Int,
        scrollOffset: Binding<CGFloat>,
        onLiveScroll: @escaping (CGFloat) -> Void,
        onViewportFrameChange: @escaping (CGRect) -> Void,
        onRenderFrameChange: @escaping (CGFloat, CGFloat) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.contentWidth = contentWidth
        self.viewportHeight = viewportHeight
        self.renderBucketWidth = renderBucketWidth
        self.hostOrigin = hostOrigin
        self.hostWidth = hostWidth
        self.contentVersion = contentVersion
        _scrollOffset = scrollOffset
        self.onLiveScroll = onLiveScroll
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
        context.coordinator.lastContentVersion = contentVersion
        context.coordinator.updateHostedFrame(in: scrollView)

        DispatchQueue.main.async {
            context.coordinator.reportViewport(scrollView)
            context.coordinator.reportRenderWindow(scrollView, force: true)
        }

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        // 中身が変わったときだけSwiftUIツリーを差し替える。
        // スクロールのたびに丸ごと作り直すとカクつくため。
        if context.coordinator.lastContentVersion != contentVersion {
            context.coordinator.lastContentVersion = contentVersion
            context.coordinator.host?.rootView = hostedContent
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

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: TimelineNativeScrollViewport<Content>
        var host: UIHostingController<AnyView>?
        var lastContentVersion: Int?
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
            // スクロール中は SwiftUI の状態(@State)に書き込まない。
            // 書き込むと毎フレーム画面全体が再計算されてカクつく。
            parent.onLiveScroll(clampedOffset)
            reportRenderWindow(scrollView, force: false)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            commitScrollOffset(scrollView)
            if !decelerate {
                reportRenderWindow(scrollView, force: true)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            commitScrollOffset(scrollView)
            reportRenderWindow(scrollView, force: true)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            commitScrollOffset(scrollView)
            reportRenderWindow(scrollView, force: true)
        }

        // スクロールが止まったときだけ、最終位置を SwiftUI 側に反映する
        private func commitScrollOffset(_ scrollView: UIScrollView) {
            let offset = clampedContentOffset(in: scrollView)
            parent.scrollOffset = offset
            parent.onLiveScroll(offset)
        }

        func reportViewport(_ scrollView: UIScrollView) {
            let frame = scrollView.convert(scrollView.bounds, to: nil)
            parent.onViewportFrameChange(frame)
        }

        func reportRenderWindow(_ scrollView: UIScrollView, force: Bool) {
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

private struct TimelineRenderWindowKey: Equatable, Hashable {
    let presentationVersion: Int
    let renderOffset: Int
    let viewportWidth: Int
    let contentWidth: Int
    let maxSeconds: Int
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
            && lhs.resizeAutoScrollTranslation == rhs.resizeAutoScrollTranslation
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
            && lhs.resizeAutoScrollTranslation == rhs.resizeAutoScrollTranslation
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
        LongPressGesture(minimumDuration: 0.16)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($dragState) { value, state, _ in
                switch value {
                case .first(true):
                    state = .pressing
                case .second(true, let drag):
                    // 長押しが成立してブロックが持ち上がった瞬間に一度だけ振動させる
                    if state == .pressing, drag == nil {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
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
