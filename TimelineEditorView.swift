//
//  TimelineEditorView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/29.
//

import SwiftData
import SwiftUI

struct TimelineEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let match: Match

    @State private var selectedScope: TimelineScope = .all
    @State private var selectedEvent: StatEvent?
    @State private var selectedTimelineEventID: UUID?
    @State private var events: [StatEvent] = []
    @State private var players: [Player] = []
    @State private var teams: [Team] = []
    @State private var didLoad = false
    @State private var saveErrorMessage: String?
    @State private var timelineZoom: CGFloat = 1.0
    @State private var baseTimelineZoom: CGFloat = 1.0
    @State private var isEventListExpanded = false
    @State private var pendingTimelineSaveTask: Task<Void, Never>?
    @State private var timelineViewportFrame: CGRect = .zero
    @State private var timelineAutoScrollAccumulatedPixels: CGFloat = 0
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var timelinePanStartOffset: CGFloat?
    @State private var timelineAutoScrollTask: Task<Void, Never>?
    @State private var timelineAutoScrollDirection = 0
    @State private var timelineAutoScrollMaxSeconds = 0
    @State private var timelineAutoScrollIntensity: CGFloat = 0

    private let minimumTimelineZoom: CGFloat = 0.05
    private let maximumTimelineZoom: CGFloat = 10.0
    private let resizeSensitivity: CGFloat = 1.35
    private let timelineAutoScrollEdgeInset: CGFloat = 76
    private let timelineAutoScrollStep: CGFloat = 34

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
        Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
    }

    private var editableEvents: [StatEvent] {
        sortedEditableEvents(from: events, half: selectedScope.half)
    }

    private var scoringEvents: [StatEvent] {
        events
            .filter { ScoringCategory(rawValue: $0.category) != nil }
            .sorted { lhs, rhs in
                if lhs.half != rhs.half { return lhs.half < rhs.half }
                if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
                return eventSortRank(lhs.category, outcome: lhs.outcome) < eventSortRank(rhs.category, outcome: rhs.outcome)
            }
    }

    private var scoringProgression: [UUID: (home: Int, away: Int)] {
        var home = 0
        var away = 0
        var progression: [UUID: (Int, Int)] = [:]

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

    var body: some View {
        ZStack {
            timelineBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if didLoad {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 10) {
                            matchInfoCard
                            scopePicker
                            trackSummary
                            horizontalTimeline
                            eventListToggle
                            if isEventListExpanded {
                                eventList
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 18)
                    }
                } else {
                    loadingView
                }
            }

        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadDataIfNeeded)
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
                onAdjust: { delta in adjust(event, by: delta) }
            )
            .presentationDetents([.medium])
        }
        .onDisappear {
            pendingTimelineSaveTask?.cancel()
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
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    reloadData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("記録データを再読み込み")
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 12)
        .padding(.top, 4)
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
        let visible = editableEvents
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("編集トラック", systemImage: "slider.horizontal.3")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(visible.count)件")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 8) {
                metricChip("得点", count: visible.filter { ScoringCategory(rawValue: $0.category) != nil }.count, color: .blue)
                metricChip("セット", count: visible.filter { $0.category == "lineout" || $0.category == "scrum" }.count, color: .teal)
                metricChip("区間", count: visible.filter { $0.category == "possession" }.count, color: .indigo)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(trackDefinitions) { track in
                    trackBadge(track, count: visible.filter { track.matches($0, match) }.count)
                }
            }
        }
        .padding(12)
        .timelineCard()
    }

    private var horizontalTimeline: some View {
        let visible = editableEvents
        let maxSeconds = timelineMaxSeconds(for: visible)
        let contentWidth = timelineContentWidth(maxSeconds: maxSeconds)

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

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        timelineRuler(maxSeconds: maxSeconds, contentWidth: contentWidth)
                        matchTimelineTrack(maxSeconds: maxSeconds, contentWidth: contentWidth)
                        ForEach(trackDefinitions) { track in
                            timelineTrackRow(track, events: visible, maxSeconds: maxSeconds, contentWidth: contentWidth)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(width: contentWidth + 112, alignment: .leading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(timelineZoomGesture)
                    .offset(x: -timelineScrollOffset)
                }
                .frame(width: geometry.size.width, height: timelineViewportHeight, alignment: .topLeading)
                .clipped()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: TimelineViewportFramePreferenceKey.self, value: proxy.frame(in: .global))
                    }
                )
                .onPreferenceChange(TimelineViewportFramePreferenceKey.self) { frame in
                    if timelineViewportFrame != frame {
                        timelineViewportFrame = frame
                    }
                }
                .gesture(timelinePanGesture(contentWidth: contentWidth + 112, viewportWidth: geometry.size.width))
                .onChange(of: contentWidth) { _, _ in
                    timelineScrollOffset = clampedTimelineScrollOffset(timelineScrollOffset, contentWidth: contentWidth + 112, viewportWidth: geometry.size.width)
                }
            }
            .frame(height: timelineViewportHeight)
        }
        .padding(12)
        .timelineCard()
    }

    private var timelineViewportHeight: CGFloat {
        CGFloat(28 + 44 + trackDefinitions.count * 44 + 12)
    }

    private func timelinePanGesture(contentWidth: CGFloat, viewportWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if timelinePanStartOffset == nil {
                    timelinePanStartOffset = timelineScrollOffset
                }
                let start = timelinePanStartOffset ?? timelineScrollOffset
                timelineScrollOffset = clampedTimelineScrollOffset(
                    start - value.translation.width,
                    contentWidth: contentWidth,
                    viewportWidth: viewportWidth
                )
            }
            .onEnded { _ in
                timelinePanStartOffset = nil
            }
    }

    private func clampedTimelineScrollOffset(_ offset: CGFloat, contentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        min(max(0, offset), max(0, contentWidth - viewportWidth))
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

    private func timelineRuler(maxSeconds: Int, contentWidth: CGFloat) -> some View {
        let ticks = timelineTicks(maxSeconds: maxSeconds)

        return HStack(spacing: 0) {
            Text("TRACK")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.44))
                .frame(width: 96, alignment: .leading)

            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { second in
                    VStack(spacing: 4) {
                        Text(timelineRulerText(for: second))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.52))
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 1, height: 8)
                    }
                    .offset(x: xOffset(for: second, maxSeconds: maxSeconds, contentWidth: contentWidth))
                }

                if selectedScope == .all {
                    halfDivider(maxSeconds: maxSeconds, contentWidth: contentWidth)
                    Text("後半 00:00")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.blue)
                        .offset(x: xOffset(for: halfTimelineOffset(for: 1), maxSeconds: maxSeconds, contentWidth: contentWidth) + 4, y: 0)
                }
            }
            .frame(width: contentWidth, height: 28, alignment: .topLeading)
        }
    }

    private func matchTimelineTrack(maxSeconds: Int, contentWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 18)
                Text("MATCH")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .frame(width: 96, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 34)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTimelineEventID = nil
                    }

                matchHalfBand(half: selectedScope.half ?? 0, maxSeconds: maxSeconds, contentWidth: contentWidth)

                if selectedScope == .all {
                    matchHalfBand(half: 1, maxSeconds: maxSeconds, contentWidth: contentWidth)
                    halfDivider(maxSeconds: maxSeconds, contentWidth: contentWidth)
                }

            }
            .frame(width: contentWidth, height: 42, alignment: .leading)
        }
        .frame(height: 44)
    }

    private func matchHalfBand(half: Int, maxSeconds: Int, contentWidth: CGFloat) -> some View {
        let offset = selectedScope == .all ? halfTimelineOffset(for: half) : 0
        let duration = halfTimelineDuration(half, in: editableEvents)
        let width = max(18, CGFloat(duration) / CGFloat(max(maxSeconds, 1)) * contentWidth)
        let label = half == 0 ? "前半" : "後半"

        return HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.black))
            Text(timeText(duration))
                .font(.caption2.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 8)
        .frame(width: width, height: 28, alignment: .leading)
        .background((half == 0 ? Color.white : Color.blue).opacity(half == 0 ? 0.14 : 0.24))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .offset(x: xOffset(for: offset, maxSeconds: maxSeconds, contentWidth: contentWidth))
    }

    private func timelineTrackRow(
        _ track: TimelineTrackDefinition,
        events: [StatEvent],
        maxSeconds: Int,
        contentWidth: CGFloat
    ) -> some View {
        let trackEvents = events.filter { track.matches($0, match) }.prefix(120)

        return HStack(spacing: 0) {
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
            .frame(width: 96, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.055))
                    .frame(height: 34)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTimelineEventID = nil
                    }

                if selectedScope == .all {
                    halfDivider(maxSeconds: maxSeconds, contentWidth: contentWidth)
                }

                ForEach(trackEvents) { event in
                    timelineEventBlock(event, track: track, maxSeconds: maxSeconds, contentWidth: contentWidth)
                }
            }
            .frame(width: contentWidth, height: 42, alignment: .leading)
        }
        .frame(height: 44)
    }

    private func timelineEventBlock(
        _ event: StatEvent,
        track: TimelineTrackDefinition,
        maxSeconds: Int,
        contentWidth: CGFloat
    ) -> some View {
        let isDuration = event.category == "possession"
        let blockWidth = isDuration
            ? max(18, CGFloat(max(1, event.seconds)) / CGFloat(max(maxSeconds, 1)) * contentWidth)
            : CGFloat(34)
        let startSeconds = timelineStartSeconds(for: event)
        let eventX = xOffset(for: startSeconds, maxSeconds: maxSeconds, contentWidth: contentWidth) - (isDuration ? 0 : blockWidth / 2)
        let clampedX = min(max(0, eventX), max(0, contentWidth - blockWidth))
        let detailText = blockWidth > 52 ? (isDuration ? timeText(event.seconds) : scoreImpactText(for: event)) : nil

        return TimelineEventBlockView(
            title: timelineCategory(for: event)?.shortTitle ?? event.category.uppercased(),
            detail: detailText,
            width: blockWidth,
            baseX: clampedX,
            maxX: max(0, contentWidth - blockWidth),
            color: track.color,
            isFailed: event.outcome == "fail",
            isDuration: isDuration,
            isSelected: selectedTimelineEventID == event.id,
            resizeSensitivity: resizeSensitivity,
            resizeAutoScrollTranslation: selectedTimelineEventID == event.id ? timelineAutoScrollAccumulatedPixels : 0,
            onTap: {
                if selectedTimelineEventID == event.id {
                    selectedTimelineEventID = nil
                } else {
                    selectedTimelineEventID = event.id
                }
            },
            onDragEnded: { translation in
                let secondsDelta = Int((translation / timelinePointsPerSecond(maxSeconds: maxSeconds, contentWidth: contentWidth)).rounded())
                guard secondsDelta != 0 else { return }
                let updatedSecond = clampedTimelineSecond(for: event, proposedSecond: startSeconds + secondsDelta)
                updateTimelineEvent(event, toTimelineSecond: updatedSecond)
            },
            onResizeStartEnded: { translation in
                defer { resetTimelineAutoScroll() }
                let resizePixels = resizeTranslation(translation) + timelineAutoScrollAccumulatedPixels
                let secondsDelta = Int((resizePixels / timelinePointsPerSecond(maxSeconds: maxSeconds, contentWidth: contentWidth)).rounded())
                guard secondsDelta != 0 else { return }
                updateTimelineIntervalEvent(
                    event,
                    proposedStartTimelineSecond: startSeconds + secondsDelta,
                    proposedEndTimelineSecond: startSeconds + event.seconds
                )
            },
            onResizeEndEnded: { translation in
                defer { resetTimelineAutoScroll() }
                let resizePixels = resizeTranslation(translation) + timelineAutoScrollAccumulatedPixels
                let secondsDelta = Int((resizePixels / timelinePointsPerSecond(maxSeconds: maxSeconds, contentWidth: contentWidth)).rounded())
                guard secondsDelta != 0 else { return }
                updateTimelineIntervalEvent(
                    event,
                    proposedStartTimelineSecond: startSeconds,
                    proposedEndTimelineSecond: startSeconds + event.seconds + secondsDelta
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
    }

    private func timelineMaxSeconds(for visibleEvents: [StatEvent]) -> Int {
        let maxSeconds: Int
        if let half = selectedScope.half {
            maxSeconds = halfTimelineDuration(half, in: visibleEvents)
        } else {
            maxSeconds = halfTimelineDuration(0, in: visibleEvents) + halfTimelineDuration(1, in: visibleEvents)
        }
        let rounded = Int(ceil(Double(max(maxSeconds, 60)) / 60.0)) * 60
        return max(60, rounded)
    }

    private func updateTimelineEvent(_ event: StatEvent, toTimelineSecond timelineSecond: Int) {
        if event.category == "possession" {
            event.startSeconds = timelineLocalSeconds(from: timelineSecond, half: event.half)
        } else {
            event.seconds = timelineLocalSeconds(from: timelineSecond, half: event.half)
        }

        saveErrorMessage = nil
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
        let halfEnd = halfStart + halfTimelineDuration(event.half, in: editableEvents)
        let start = min(max(halfStart, proposedStartTimelineSecond), max(halfStart, halfEnd - 1))
        let end = min(max(start + 1, proposedEndTimelineSecond), halfEnd)

        event.startSeconds = timelineLocalSeconds(from: start, half: event.half)
        event.seconds = max(1, end - start)

        saveErrorMessage = nil
        scheduleTimelineSave()
    }

    private func resizeTranslation(_ translation: CGFloat) -> CGFloat {
        translation * resizeSensitivity
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

        let normalizedOverflow = min(1.0, overflow / timelineAutoScrollEdgeInset)
        startTimelineAutoScroll(
            direction: direction,
            maxSeconds: maxSeconds,
            intensity: normalizedOverflow
        )
        advanceTimelineAutoScroll(
            direction: direction,
            maxSeconds: maxSeconds,
            step: timelineAutoScrollStep * (0.35 + normalizedOverflow)
        )
    }

    private func startTimelineAutoScroll(direction: Int, maxSeconds: Int, intensity: CGFloat) {
        timelineAutoScrollDirection = direction
        timelineAutoScrollMaxSeconds = maxSeconds
        timelineAutoScrollIntensity = intensity

        guard timelineAutoScrollTask == nil else { return }

        timelineAutoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                guard timelineAutoScrollDirection != 0 else { break }
                let step = timelineAutoScrollStep * (0.75 + timelineAutoScrollIntensity * 2.4)
                advanceTimelineAutoScroll(
                    direction: timelineAutoScrollDirection,
                    maxSeconds: timelineAutoScrollMaxSeconds,
                    step: step
                )
                try? await Task.sleep(for: .milliseconds(95))
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
            contentWidth: contentWidth + 112,
            viewportWidth: timelineViewportFrame.width
        )

        let pixelDelta = timelineScrollOffset - previousOffset
        if pixelDelta != 0 {
            timelineAutoScrollAccumulatedPixels += pixelDelta
        }
    }

    private func stopTimelineAutoScroll() {
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

    private var pointsPerSecond: CGFloat {
        2.4 * timelineZoom
    }

    private var zoomText: String {
        String(format: "x%.1f", Double(timelineZoom))
    }

    private var timelineZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                timelineZoom = clampedTimelineZoom(baseTimelineZoom * value)
            }
            .onEnded { value in
                setTimelineZoom(baseTimelineZoom * value)
            }
    }

    private func setTimelineZoom(_ zoom: CGFloat) {
        timelineZoom = clampedTimelineZoom(zoom)
        baseTimelineZoom = timelineZoom
    }

    private func clampedTimelineZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumTimelineZoom, max(minimumTimelineZoom, zoom))
    }

    private func clampedTimelineSecond(for event: StatEvent, proposedSecond: Int) -> Int {
        let halfStart = halfTimelineOffset(for: event.half)
        let halfEnd = halfStart + halfTimelineDuration(event.half, in: editableEvents)
        let latestStart = event.category == "possession"
            ? max(halfStart, halfEnd - max(0, event.seconds))
            : halfEnd
        return min(max(halfStart, proposedSecond), latestStart)
    }

    private func timelineLocalSeconds(from timelineSecond: Int, half: Int) -> Int {
        max(0, timelineSecond - halfTimelineOffset(for: half))
    }

    private func timelineStartSeconds(for event: StatEvent) -> Int {
        let halfOffset = halfTimelineOffset(for: event.half)
        if event.category == "possession" {
            return halfOffset + (event.startSeconds ?? inferredPossessionStartSecondsWithinHalf(for: event))
        }
        return halfOffset + event.seconds
    }

    private func halfTimelineOffset(for half: Int) -> Int {
        guard selectedScope == .all, half >= 1 else { return 0 }
        return halfTimelineDuration(0, in: editableEvents)
    }

    private func halfTimelineDuration(_ half: Int, in visibleEvents: [StatEvent]) -> Int {
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
        return max(maxPointSeconds, maxStoredPossessionEnd, homeAwayDuration, bipDuration, 60)
    }

    private func inferredPossessionStartSecondsWithinHalf(for event: StatEvent) -> Int {
        guard event.category == "possession" else { return event.seconds }

        let isBIP = event.outcome == "none"
        var start = 0
        for candidate in possessionEventsInRecordedOrder(half: event.half, includesBIP: isBIP) {
            if candidate.id == event.id {
                return start
            }
            start += max(0, candidate.seconds)
        }
        return 0
    }

    private func possessionEventsInRecordedOrder(half: Int, includesBIP: Bool) -> [StatEvent] {
        events.filter { event in
            event.category == "possession"
                && event.half == half
                && ((event.outcome == "none") == includesBIP)
        }
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

    private func halfDivider(maxSeconds: Int, contentWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.blue.opacity(0.75))
            .frame(width: 2, height: 34)
            .offset(x: xOffset(for: halfTimelineOffset(for: 1), maxSeconds: maxSeconds, contentWidth: contentWidth))
    }

    private func timelineContentWidth(maxSeconds: Int) -> CGFloat {
        max(240, CGFloat(maxSeconds) * pointsPerSecond)
    }

    private func timelineTicks(maxSeconds: Int) -> [Int] {
        let interval = timelineTickInterval(maxSeconds: maxSeconds)
        return stride(from: 0, through: maxSeconds, by: interval).map { $0 }
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
        let targetSeconds = 130 / max(effectivePointsPerSecond, 0.1)
        let candidates = [10, 15, 30, 60, 120, 180, 300, 600]
        return candidates.first { Double($0) >= Double(targetSeconds) } ?? 600
    }

    private func timelinePointsPerSecond(maxSeconds: Int, contentWidth: CGFloat) -> CGFloat {
        contentWidth / CGFloat(max(maxSeconds, 1))
    }


    private func xOffset(for seconds: Int, maxSeconds: Int, contentWidth: CGFloat) -> CGFloat {
        CGFloat(max(0, seconds)) / CGFloat(max(maxSeconds, 1)) * contentWidth
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
    }

    private func loadDataIfNeeded() {
        guard !didLoad else { return }
        reloadData()
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
            didLoad = true
        } catch {
            events = []
            players = []
            teams = []
            didLoad = true
        }
    }

    private func adjust(_ event: StatEvent, by delta: Int) -> Int {
        let previousSeconds = event.seconds
        event.seconds = max(0, event.seconds + delta)

        do {
            try modelContext.save()
            saveErrorMessage = nil
            events = sortedEditableEvents(from: events, half: nil) + events.filter { timelineCategory(for: $0) == nil }
        } catch {
            event.seconds = previousSeconds
            saveErrorMessage = "時刻の変更を保存できませんでした。もう一度試してください。"
        }

        return event.seconds
    }

    private func sortedEditableEvents(from source: [StatEvent], half: Int?) -> [StatEvent] {
        source
            .filter { timelineCategory(for: $0) != nil }
            .filter { half == nil || $0.half == half }
            .sorted { lhs, rhs in
                if lhs.half != rhs.half { return lhs.half < rhs.half }
                let lhsSecond = timelineSortSecond(for: lhs)
                let rhsSecond = timelineSortSecond(for: rhs)
                if lhsSecond != rhsSecond { return lhsSecond < rhsSecond }
                return eventSortRank(lhs.category, outcome: lhs.outcome) < eventSortRank(rhs.category, outcome: rhs.outcome)
            }
    }

    private func timelineSortSecond(for event: StatEvent) -> Int {
        if event.category == "possession" {
            return event.startSeconds ?? inferredPossessionStartSecondsWithinHalf(for: event)
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

    private var trackDefinitions: [TimelineTrackDefinition] {
        [
            TimelineTrackDefinition(title: "HOME", systemImage: "house.fill", color: .blue) { event, match in
                event.category == "possession" && (event.teamID == match.homeTeamID || (event.teamID == nil && event.outcome == "own"))
            },
            TimelineTrackDefinition(title: "AWAY", systemImage: "a.circle.fill", color: .red) { event, match in
                event.category == "possession" && (event.teamID == match.awayTeamID || (event.teamID == nil && event.outcome == "opponent"))
            },
            TimelineTrackDefinition(title: "BIP", systemImage: "clock.fill", color: .indigo) { event, _ in
                event.category == "possession" && event.outcome == "none"
            },
            TimelineTrackDefinition(title: "TRY", systemImage: "rugbyball.fill", color: .purple) { event, _ in
                event.category == "try"
            },
            TimelineTrackDefinition(title: "CONV", systemImage: "figure.rugby", color: .green) { event, _ in
                event.category == "conversion"
            },
            TimelineTrackDefinition(title: "PG", systemImage: "p.circle.fill", color: .yellow) { event, _ in
                event.category == "penalty_goal"
            },
            TimelineTrackDefinition(title: "DG", systemImage: "d.circle.fill", color: .yellow) { event, _ in
                event.category == "drop_goal"
            },
            TimelineTrackDefinition(title: "LO", systemImage: "figure.strengthtraining.traditional", color: .teal) { event, _ in
                event.category == "lineout"
            },
            TimelineTrackDefinition(title: "SCR", systemImage: "person.3.fill", color: .orange) { event, _ in
                event.category == "scrum"
            }
        ]
    }
}

private struct TimelineEventBlockView: View, Equatable {
    let title: String
    let detail: String?
    let width: CGFloat
    let baseX: CGFloat
    let maxX: CGFloat
    let color: Color
    let isFailed: Bool
    let isDuration: Bool
    let isSelected: Bool
    let resizeSensitivity: CGFloat
    let resizeAutoScrollTranslation: CGFloat
    let onTap: () -> Void
    let onDragEnded: (CGFloat) -> Void
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
            && lhs.baseX == rhs.baseX
            && lhs.maxX == rhs.maxX
            && lhs.isFailed == rhs.isFailed
            && lhs.isDuration == rhs.isDuration
            && lhs.isSelected == rhs.isSelected
            && lhs.resizeSensitivity == rhs.resizeSensitivity
            && lhs.resizeAutoScrollTranslation == rhs.resizeAutoScrollTranslation
    }

    private var currentX: CGFloat {
        return min(max(0, baseX + dragState.translation), maxX)
    }

    private var previewX: CGFloat {
        if let leftTranslation = resizeState.leftTranslation {
            return min(max(-baseX, resizePreviewTranslation(leftTranslation) + resizeAutoScrollTranslation), width - minimumDurationWidth)
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
        isSelected ? 2 : 7
    }

    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0))
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
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
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
        ZStack(alignment: .leading) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                if let detail {
                    Text(detail)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
            .padding(.horizontal, isDuration ? 14 : 7)

            if isDuration && isSelected {
                HStack(spacing: 0) {
                    resizeHandle(edge: .start)
                    Spacer(minLength: 0)
                    resizeHandle(edge: .end)
                }
            }

        }
        .foregroundStyle(.white)
        .frame(width: displayedWidth, height: 28)
        .background(color.opacity(isFailed ? 0.42 : 0.78))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(outlineColor, lineWidth: (isLifted || isResizing || isSelected) ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .scaleEffect(isLifted ? 1.05 : 1.0)
        .offset(x: displayedX)
        .offset(y: isLifted ? -4 : 0)
        .shadow(color: .black.opacity(isLifted ? 0.38 : 0), radius: 10, x: 0, y: 8)
        .zIndex(isLifted ? 3 : 1)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onTapGesture(perform: onTap)
        .simultaneousGesture(dragGesture)
    }

    private func resizeHandle(edge: ResizeEdge) -> some View {
        Rectangle()
            .fill(Color.white.opacity(resizeState.edge == edge ? 1.0 : 0.94))
            .frame(width: 22, height: 26)
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.48))
                    .frame(width: 3, height: 15)
            )
            .frame(width: 24, height: 28)
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
        onAdjust: @escaping (Int) -> Int
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

private struct TimelineViewportFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private enum TimelineResizeEdge: Equatable {
    case start
    case end
}

private enum TimelineEventCategory {
    case homePossession
    case awayPossession
    case bip
    case tryScore
    case conversion
    case penaltyGoal
    case dropGoal
    case lineout
    case scrum

    var title: String {
        switch self {
        case .homePossession: return "HOMEポゼッション"
        case .awayPossession: return "AWAYポゼッション"
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
        case .homePossession: return .blue
        case .awayPossession: return .red
        case .bip: return .indigo
        case .tryScore: return .purple
        case .conversion: return .green
        case .penaltyGoal, .dropGoal: return .yellow
        case .lineout: return .teal
        case .scrum: return .orange
        }
    }
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
