import SwiftUI

/// Floating controls shown while recording.
struct RecorderPill: View {
    @ObservedObject var recorder: AudioRecorderController
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(recorder.state == .paused ? 0.35 : 1)

            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                Text(clockString(recorder.elapsed))
                    .font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
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

/// Floating playback controls with a scrubber.
struct PlayerPill: View {
    @ObservedObject var player: AudioPlayerController
    @State private var dragging = false
    @State private var dragValue: Double = 0

    private let speeds: [Double] = [0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        HStack(spacing: 12) {
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 24)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

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
            .frame(width: 270)

            Menu {
                ForEach(speeds, id: \.self) { speed in
                    Button("\(speed.formatted())×") { player.setRate(Float(speed)) }
                }
            } label: {
                Text("\(Double(player.rate).formatted())×").font(.caption.weight(.semibold))
            }

            Button { player.close() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Close player")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .floatingCapsule()
    }
}

/// All the recordings of one note, with their timestamp markers.
struct RecordingsSheet: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject var player: AudioPlayerController
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID

    @State private var renaming: NoteRecording?
    @State private var renameText = ""
    @State private var showRename = false
    @State private var deleting: NoteRecording?
    @State private var errorText: String?

    private var recordings: [NoteRecording] {
        (store.note(noteID)?.recordings ?? []).sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if recordings.isEmpty {
                    ContentUnavailableView("No Recordings", systemImage: "waveform",
                                           description: Text("Tap the microphone to record while you write."))
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
            .toolbar { Button("Done") { dismiss() } }
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
            .alert("Can't play this recording",
                   isPresented: Binding(get: { errorText != nil },
                                        set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
        }
        .presentationDetents([.medium, .large])
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
