import SwiftUI
import UniformTypeIdentifiers

// MARK: - While recording

/// A few bars that move with the sound the microphone is hearing.
struct LevelMeter: View {
    let level: Float
    private let weights: [CGFloat] = [0.55, 0.85, 1.0, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: 5 + CGFloat(level) * 17 * weights[index])
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

/// Floating controls shown while recording: input meter, timer, pause, timestamp, stop.
struct RecorderPill: View {
    @ObservedObject var recorder: AudioRecorderController
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                HStack(spacing: 10) {
                    LevelMeter(level: recorder.level)
                    Text(clockString(recorder.elapsed))
                        .font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
                        .opacity(recorder.state == .paused ? 0.5 : 1)
                }
            }

            Button {
                if recorder.state == .paused { recorder.resume() } else { recorder.pause() }
            } label: {
                Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
            }
            .accessibilityLabel(recorder.state == .paused ? "Resume recording" : "Pause recording")

            Button { recorder.addMarker() } label: { Image(systemName: "flag.fill") }
                .accessibilityLabel("Add timestamp marker")

            Button(action: onStop) {
                Image(systemName: "stop.fill").foregroundStyle(Color.red)
            }
            .accessibilityLabel("Stop recording")
        }
        .font(.body)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .floatingCapsule()
    }
}

// MARK: - Playback

/// Floating playback controls: play, back and forward 10 seconds, a scrubber and speed.
struct PlayerPill: View {
    @ObservedObject var player: AudioPlayerController
    let onTranscript: () -> Void

    @State private var dragging = false
    @State private var dragValue: Double = 0

    private let speeds: [Double] = [0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        HStack(spacing: 12) {
            Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                .accessibilityLabel("Back 10 seconds")

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 26)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button { player.skip(by: 10) } label: { Image(systemName: "goforward.10") }
                .accessibilityLabel("Forward 10 seconds")

            TimelineView(.animation(minimumInterval: 0.1, paused: !player.isPlaying && !dragging)) { _ in
                let value = dragging ? dragValue : player.currentTime
                HStack(spacing: 8) {
                    Text(clockString(value)).font(.caption.monospacedDigit())
                    Slider(value: Binding(get: { value }, set: { dragValue = $0 }),
                           in: 0...max(player.duration, 0.1)) { editing in
                        if editing { dragValue = player.currentTime }
                        dragging = editing
                        if !editing { player.seek(to: dragValue) }
                    }
                    Text(clockString(player.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 230)

            Menu {
                ForEach(speeds, id: \.self) { speed in
                    Button("\(speed.formatted())×") { player.setRate(Float(speed)) }
                }
            } label: {
                Text("\(Double(player.rate).formatted())×").font(.caption.weight(.semibold))
            }

            Button(action: onTranscript) { Image(systemName: "text.alignleft") }
                .accessibilityLabel("Transcript")

            Button { player.close() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Close playback")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .floatingCapsule()
    }
}

// MARK: - Manage recordings

/// All the recordings of one note: play, rename, trim, split, transcribe, import, delete.
struct RecordingsSheet: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject var player: AudioPlayerController
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID

    @State private var renaming: NoteRecording?
    @State private var renameText = ""
    @State private var showRename = false
    @State private var deleting: NoteRecording?
    @State private var trimming: NoteRecording?
    @State private var transcribing: NoteRecording?
    @State private var showImporter = false
    @State private var busy = false
    @State private var errorText: String?

    private var recordings: [NoteRecording] {
        (store.note(noteID)?.recordings ?? []).sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if recordings.isEmpty {
                    ContentUnavailableView("No Recordings", systemImage: "waveform",
                                           description: Text("Tap the microphone to record while you write, or import an audio file."))
                }
                ForEach(recordings) { recording in
                    Section {
                        row(recording)
                        ForEach(recording.markers) { marker in markerRow(recording, marker) }
                    }
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showImporter = true } label: { Label("Import Audio", systemImage: "square.and.arrow.down") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .overlay {
                if busy {
                    ProgressView("Working…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.medium))
                }
            }
            .alert("Rename Recording", isPresented: $showRename) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let renaming, !name.isEmpty {
                        store.renameRecording(noteID, recordingID: renaming.id, to: name)
                    }
                }
            }
            .confirmationDialog("Delete this recording?",
                                isPresented: Binding(get: { deleting != nil },
                                                     set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible,
                                presenting: deleting) { recording in
                Button("Delete Recording", role: .destructive) {
                    if player.current?.id == recording.id { player.close() }
                    store.deleteRecording(noteID, recordingID: recording.id)
                }
            } message: { _ in Text("The audio will be removed. Your handwriting stays.") }
            .alert("Something went wrong",
                   isPresented: Binding(get: { errorText != nil },
                                        set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
            .sheet(item: $trimming) { recording in
                TrimSheet(recording: recording) { start, end in
                    run {
                        if player.current?.id == recording.id { player.close() }
                        try await store.trimRecording(noteID: noteID, recordingID: recording.id, from: start, to: end)
                    }
                }
            }
            .sheet(item: $transcribing) { recording in
                TranscriptSheet(player: player, noteID: noteID, recordingID: recording.id)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
                switch result {
                case .success(let url):
                    run { try await store.importAudio(from: url, to: noteID) }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Runs a slow audio job with a spinner, and shows any error.
    private func run(_ job: @escaping () async throws -> Void) {
        Task {
            busy = true
            defer { busy = false }
            do {
                try await job()
                Haptics.success()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func row(_ recording: NoteRecording) -> some View {
        let isCurrent = player.current?.id == recording.id
        return HStack(spacing: 14) {
            Button { play(recording, at: 0) } label: {
                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 3) {
                Text(recording.title).font(.body.weight(.semibold))
                Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened)
                     + " · " + clockString(recording.duration)
                     + (recording.hasAudio ? "" : " · audio not on this device"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Menu {
                Button { transcribing = recording } label: {
                    Label(recording.transcript == nil ? "Transcribe…" : "Transcript", systemImage: "text.alignleft")
                }
                .disabled(!recording.hasAudio)
                Button { trimming = recording } label: { Label("Trim…", systemImage: "scissors") }
                    .disabled(!recording.hasAudio || recording.duration < 3)
                Button { split(recording) } label: { Label("Split at Playhead", systemImage: "square.split.2x1") }
                    .disabled(!(isCurrent && player.currentTime > 1 && player.currentTime < recording.duration - 1))
                Button {
                    renaming = recording
                    renameText = recording.title
                    showRename = true
                } label: { Label("Rename", systemImage: "pencil") }
                if recording.hasAudio {
                    ShareLink(item: recording.fileURL) { Label("Share Audio", systemImage: "square.and.arrow.up") }
                }
                Divider()
                Button(role: .destructive) { deleting = recording } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
        }
    }

    private func markerRow(_ recording: NoteRecording, _ marker: RecordingMarker) -> some View {
        Button { play(recording, at: marker.time) } label: {
            HStack {
                Image(systemName: "flag.fill").foregroundStyle(Color.orange)
                Text(marker.label)
                Spacer()
                Text(clockString(marker.time)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }

    private func split(_ recording: NoteRecording) {
        let time = player.currentTime
        run {
            player.close()
            try await store.splitRecording(noteID: noteID, recordingID: recording.id, at: time)
        }
    }

    private func play(_ recording: NoteRecording, at time: TimeInterval) {
        do {
            if time == 0, player.current?.id == recording.id {
                player.toggle()
            } else {
                try player.open(recording, at: time, play: true)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Trim

struct TrimSheet: View {
    let recording: NoteRecording
    let onApply: (TimeInterval, TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Double = 0
    @State private var end: Double

    init(recording: NoteRecording, onApply: @escaping (TimeInterval, TimeInterval) -> Void) {
        self.recording = recording
        self.onApply = onApply
        _end = State(initialValue: recording.duration)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start of the part to keep: \(clockString(start))") {
                    Slider(value: $start, in: 0...max(0.1, end - 1))
                }
                Section("End of the part to keep: \(clockString(end))") {
                    Slider(value: $end, in: min(start + 1, recording.duration)...recording.duration)
                }
                Section {
                    Text("Kept: \(clockString(end - start)) of \(clockString(recording.duration)). The rest of the audio is removed for good. Your handwriting is not changed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Trim Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Trim") {
                        onApply(start, end)
                        dismiss()
                    }
                    .disabled(end - start < 1 || (start == 0 && end >= recording.duration))
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Transcript

/// The words of a recording, each line with its time. Tap a line to hear it.
struct TranscriptSheet: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject var player: AudioPlayerController
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID
    let recordingID: UUID

    @State private var working = false
    @State private var errorText: String?

    private var recording: NoteRecording? {
        store.note(noteID)?.recordings.first { $0.id == recordingID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let recording {
                    if let segments = recording.transcript, !segments.isEmpty {
                        list(recording, segments)
                    } else {
                        empty(recording)
                    }
                } else {
                    ContentUnavailableView("Recording not found", systemImage: "waveform.slash")
                }
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .alert("Couldn't transcribe",
                   isPresented: Binding(get: { errorText != nil },
                                        set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
        }
        .presentationDetents([.medium, .large])
    }

    private func empty(_ recording: NoteRecording) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "text.alignleft").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("No transcript yet").font(.headline)
            Text("The words are worked out on this device. The audio is never uploaded.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if working {
                ProgressView("Transcribing…")
            } else {
                Button("Transcribe") { transcribe(recording) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!recording.hasAudio)
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
    }

    private func list(_ recording: NoteRecording, _ segments: [TranscriptSegment]) -> some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { _ in
            let now: TimeInterval = player.current?.id == recording.id ? player.currentTime : -1
            List(Array(segments.enumerated()), id: \.element.id) { index, segment in
                let end = index + 1 < segments.count ? segments[index + 1].time : recording.duration
                let isCurrent = now >= segment.time && now < end
                Button {
                    do {
                        try player.open(recording, at: segment.time, play: true)
                    } catch {
                        errorText = error.localizedDescription
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(clockString(segment.time))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)
                        Text(segment.text)
                            .fontWeight(isCurrent ? .semibold : .regular)
                    }
                }
                .foregroundStyle(.primary)
                .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
            }
        }
    }

    private func transcribe(_ recording: NoteRecording) {
        Task {
            working = true
            defer { working = false }
            do {
                let segments = try await Transcriber.transcribe(recording.fileURL)
                if segments.isEmpty {
                    errorText = "No speech was found in this recording."
                } else {
                    store.setTranscript(noteID, recordingID: recording.id, segments: segments)
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
