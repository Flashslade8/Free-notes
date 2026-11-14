import SwiftUI
import AVFoundation
import PencilKit
import Speech

// MARK: - Data

struct RecordingPause: Codable, Equatable {
    var start: Date
    var end: Date
}

/// A timestamp you dropped while recording.
struct RecordingMarker: Identifiable, Codable, Equatable {
    var id = UUID()
    var time: TimeInterval          // seconds into the audio
    var label: String
}

/// A lecture or conversation recorded inside a note.
/// Only this description is synced. The audio file stays on the device that recorded it.
/// One line of a transcript, with when it was said.
struct TranscriptSegment: Identifiable, Codable, Equatable {
    var id = UUID()
    var time: TimeInterval          // seconds into the audio
    var text: String
}

struct NoteRecording: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval      // length of the audio itself (pauses not included)
    var pauses: [RecordingPause] = []
    var markers: [RecordingMarker] = []
    var trimStart: TimeInterval? = nil      // seconds cut from the start of the original audio
    var transcript: [TranscriptSegment]? = nil

    var trim: TimeInterval { trimStart ?? 0 }

    var fileURL: URL { RecordingFiles.url(for: id) }
    var hasAudio: Bool { RecordingFiles.exists(id) }

    /// Where in the audio something written at `date` belongs, or nil if the
    /// recording wasn't running then (or that part was trimmed away).
    /// Time spent paused is taken out.
    func offset(for date: Date) -> TimeInterval? {
        guard date >= startedAt, date <= endedAt else { return nil }
        var paused: TimeInterval = 0
        var raw: TimeInterval?
        for pause in pauses.sorted(by: { $0.start < $1.start }) {
            if date >= pause.end {
                paused += pause.end.timeIntervalSince(pause.start)
            } else if date > pause.start {
                raw = max(0, pause.start.timeIntervalSince(startedAt) - paused)
                break
            }
        }
        let untrimmed = raw ?? max(0, date.timeIntervalSince(startedAt) - paused)
        let shifted = untrimmed - trim
        guard shifted >= 0, shifted <= duration + 0.5 else { return nil }
        return shifted
    }
}

enum RecordingFiles {
    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).m4a")
    }

    static func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    static func copy(from old: UUID, to new: UUID) {
        try? FileManager.default.copyItem(at: url(for: old), to: url(for: new))
    }
}

func clockString(_ time: TimeInterval) -> String {
    let total = Int(max(0, time))
    let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
}

// MARK: - Audio session

enum AudioSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }
}

// MARK: - Recorder

@MainActor
final class AudioRecorderController: ObservableObject {
    enum State { case idle, recording, paused }

    @Published private(set) var state: State = .idle
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var recordingID = UUID()
    private var startedAt = Date()
    private var pauses: [RecordingPause] = []
    private var pauseStartedAt: Date?
    private var markers: [RecordingMarker] = []
    private var interruptionToken: NSObjectProtocol?

    /// Not @Published on purpose: the clock reads it on its own timer,
    /// so the editor isn't redrawn several times a second.
    var elapsed: TimeInterval { recorder?.currentTime ?? 0 }
    var markerCount: Int { markers.count }

    /// How loud the room is right now, from 0 (silent) to 1. Read by the on-screen meter.
    var level: Float {
        guard let recorder, state == .recording else { return 0 }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)      // about -60 (quiet) to 0 (loud)
        return max(0, min(1, (decibels + 50) / 50))
    }

    func start() async {
        guard state == .idle else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Microphone access is off. Turn it on in Settings › Free Notes."
            return
        }
        do {
            try AudioSession.activate()
            let id = UUID()
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let newRecorder = try AVAudioRecorder(url: RecordingFiles.url(for: id), settings: settings)
            newRecorder.isMeteringEnabled = true
            guard newRecorder.prepareToRecord(), newRecorder.record() else {
                errorMessage = "The recording couldn't start. Check that no other app is using the microphone."
                return
            }
            recorder = newRecorder
            recordingID = id
            startedAt = Date()
            pauses = []
            markers = []
            pauseStartedAt = nil
            state = .recording
            observeInterruptions()
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        pauseStartedAt = Date()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        recorder?.record()
        if let began = pauseStartedAt {
            pauses.append(RecordingPause(start: began, end: Date()))
        }
        pauseStartedAt = nil
        state = .recording
    }

    /// Drops a timestamp at the current point in the recording.
    func addMarker() {
        guard state != .idle, let recorder else { return }
        markers.append(RecordingMarker(time: recorder.currentTime, label: "Marker \(markers.count + 1)"))
        Haptics.tap()
    }

    /// Stops and returns the finished recording (nil if it was too short to keep).
    @discardableResult
    func stop() -> NoteRecording? {
        guard let recorder, state != .idle else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        let end = Date()
        if let began = pauseStartedAt {
            pauses.append(RecordingPause(start: began, end: end))
        }
        pauseStartedAt = nil
        self.recorder = nil
        state = .idle
        if let token = interruptionToken {
            NotificationCenter.default.removeObserver(token)
            interruptionToken = nil
        }

        guard duration >= 1 else {
            RecordingFiles.delete(recordingID)
            return nil
        }
        return NoteRecording(id: recordingID,
                             title: "Recording " + startedAt.formatted(date: .omitted, time: .shortened),
                             startedAt: startedAt, endedAt: end, duration: duration,
                             pauses: pauses, markers: markers)
    }

    /// A phone call or alarm pauses the recording instead of silently losing audio.
    private func observeInterruptions() {
        interruptionToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in
                if self?.state == .recording { self?.pause() }
            }
        }
    }
}

// MARK: - Player

enum PlayerError: LocalizedError {
    case missingFile
    var errorDescription: String? {
        "The audio for this recording isn't on this device. Recordings are only kept on the device that made them."
    }
}

@MainActor
final class AudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var current: NoteRecording?
    @Published private(set) var isPlaying = false
    @Published private(set) var rate: Float = 1
    @Published private(set) var seekTick = 0      // changes on every jump so the screen follows along

    private var player: AVAudioPlayer?

    /// Not @Published — read by the on-screen clock on its own timer.
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? current?.duration ?? 0 }

    func open(_ recording: NoteRecording, at start: TimeInterval, play shouldPlay: Bool) throws {
        if current?.id != recording.id || player == nil {
            guard RecordingFiles.exists(recording.id) else { throw PlayerError.missingFile }
            try AudioSession.activate()
            let newPlayer = try AVAudioPlayer(contentsOf: recording.fileURL)
            newPlayer.enableRate = true
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            player = newPlayer
            current = recording
        }
        seek(to: start)
        if shouldPlay { play() }
    }

    func play() {
        guard let player else { return }
        player.rate = rate
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        seekTick &+= 1
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying { player?.rate = newRate }
    }

    func close() {
        player?.stop()
        player = nil
        current = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}

// MARK: - Matching handwriting to audio

enum AudioSync {
    /// The stroke closest to a tap, if one is near enough.
    static func nearestStroke(in drawing: PKDrawing, to point: CGPoint, maxDistance: CGFloat) -> PKStroke? {
        var best: (stroke: PKStroke, distance: CGFloat)?
        for stroke in drawing.strokes {
            let nearby = stroke.renderBounds.insetBy(dx: -maxDistance, dy: -maxDistance)
            guard nearby.contains(point) else { continue }

            for sample in stroke.path.interpolatedPoints(by: .distance(6)) {
                let location = sample.location.applying(stroke.transform)
                let distance = hypot(location.x - point.x, location.y - point.y)
                if distance <= maxDistance, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                    best = (stroke, distance)
                }
            }
        }
        return best?.stroke
    }
}

/// Catches taps on a page while "tap writing to hear it" is on.
struct TapOverlay: UIViewRepresentable {
    let zoom: CGFloat
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: TapOverlay
        init(_ parent: TapOverlay) { self.parent = parent }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            let z = max(parent.zoom, 0.01)
            parent.onTap(CGPoint(x: point.x / z, y: point.y / z))
        }
    }
}


// MARK: - Trimming, splitting and importing

enum AudioEditing {
    enum Failure: LocalizedError {
        case exportFailed
        var errorDescription: String? { "The audio couldn't be processed." }
    }

    /// Writes the part of `source` between `start` and `end` seconds to `destination` as .m4a.
    static func export(source: URL, from start: TimeInterval, to end: TimeInterval, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let total = (try? await asset.load(.duration).seconds) ?? end
        let stop = min(end, total.isFinite ? total : end)
        guard stop > start,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.exportFailed
        }
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                        end: CMTime(seconds: stop, preferredTimescale: 600))
        try? FileManager.default.removeItem(at: destination)

        if #available(iOS 18.0, *) {
            try await session.export(to: destination, as: .m4a)
        } else {
            session.outputURL = destination
            session.outputFileType = .m4a
            await session.export()
            guard session.status == .completed else { throw Failure.exportFailed }
        }
    }

    /// Brings an audio file (an MP3, a voice memo, anything iOS can play) into a note.
    static func importFile(_ url: URL) async throws -> NoteRecording {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        let total = try await asset.load(.duration).seconds
        guard total.isFinite, total > 0 else { throw Failure.exportFailed }

        let id = UUID()
        try await export(source: url, from: 0, to: total, destination: RecordingFiles.url(for: id))
        let now = Date()
        // Same start and end time: nothing you wrote is linked to an imported file.
        return NoteRecording(id: id, title: url.deletingPathExtension().lastPathComponent,
                             startedAt: now, endedAt: now, duration: total)
    }
}

extension NoteStore {
    private func changeRecording(_ noteID: UUID, _ recordingID: UUID, _ change: (inout NoteRecording) -> Void) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }),
              let r = notes[i].recordings.firstIndex(where: { $0.id == recordingID }) else { return }
        var recording = notes[i].recordings[r]
        change(&recording)
        notes[i].recordings[r] = recording
    }

    func setTranscript(_ noteID: UUID, recordingID: UUID, segments: [TranscriptSegment]) {
        changeRecording(noteID, recordingID) { $0.transcript = segments }
    }

    /// Cuts a recording down to the part between `start` and `end` seconds.
    func trimRecording(noteID: UUID, recordingID: UUID, from start: TimeInterval, to end: TimeInterval) async throws {
        guard let recording = note(noteID)?.recordings.first(where: { $0.id == recordingID }) else { return }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try await AudioEditing.export(source: recording.fileURL, from: start, to: end, destination: temp)
        _ = try FileManager.default.replaceItemAt(recording.fileURL, withItemAt: temp)

        changeRecording(noteID, recordingID) { r in
            let length = end - start
            r.trimStart = r.trim + start
            r.duration = length
            r.markers = r.markers.compactMap { marker in
                var m = marker
                m.time -= start
                return (m.time >= 0 && m.time <= length) ? m : nil
            }
            r.transcript = r.transcript?.compactMap { segment in
                var s = segment
                s.time -= start
                return (s.time >= 0 && s.time <= length) ? s : nil
            }
        }
    }

    /// Splits one recording into two at `time` seconds.
    func splitRecording(noteID: UUID, recordingID: UUID, at time: TimeInterval) async throws {
        guard let note = note(noteID),
              let recording = note.recordings.first(where: { $0.id == recordingID }),
              time > 1, time < recording.duration - 1 else { return }

        let newID = UUID()
        try await AudioEditing.export(source: recording.fileURL, from: time, to: recording.duration,
                                      destination: RecordingFiles.url(for: newID))

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try await AudioEditing.export(source: recording.fileURL, from: 0, to: time, destination: temp)
        _ = try FileManager.default.replaceItemAt(recording.fileURL, withItemAt: temp)

        var second = recording
        second.id = newID
        second.title = recording.title + " (part 2)"
        second.trimStart = recording.trim + time
        second.duration = recording.duration - time
        second.markers = recording.markers.filter { $0.time > time }.map {
            var m = $0
            m.time -= time
            return m
        }
        second.transcript = recording.transcript?.filter { $0.time >= time }.map {
            var s = $0
            s.time -= time
            return s
        }

        changeRecording(noteID, recordingID) { r in
            r.duration = time
            r.markers = r.markers.filter { $0.time <= time }
            r.transcript = r.transcript?.filter { $0.time < time }
        }
        addRecording(second, to: noteID)
    }

    func importAudio(from url: URL, to noteID: UUID) async throws {
        let recording = try await AudioEditing.importFile(url)
        addRecording(recording, to: noteID)
    }
}

// MARK: - Transcripts (on the device, free)

enum Transcriber {
    enum Failure: LocalizedError {
        case notAllowed, unavailable
        var errorDescription: String? {
            switch self {
            case .notAllowed:
                return "Speech recognition is off. Turn it on in Settings › Free Notes."
            case .unavailable:
                return "On-device speech recognition isn't available for your language on this device, so the audio stays untranscribed."
            }
        }
    }

    /// Turns speech into text without sending the audio anywhere.
    static func transcribe(_ url: URL) async throws -> [TranscriptSegment] {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw Failure.notAllowed }

        let candidates = [Locale.current, Locale(identifier: "en-GB"), Locale(identifier: "en-US")]
        guard let recognizer = candidates.compactMap({ SFSpeechRecognizer(locale: $0) })
            .first(where: { $0.isAvailable && $0.supportsOnDeviceRecognition }) else {
            throw Failure.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true      // never uploads the audio
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                finished = true
                continuation.resume(returning: group(result.bestTranscription.segments))
            }
        }
    }

    /// Groups single words into short lines you can tap.
    private static func group(_ words: [SFTranscriptionSegment]) -> [TranscriptSegment] {
        var lines: [TranscriptSegment] = []
        var current: [String] = []
        var start: TimeInterval = 0
        var lastEnd: TimeInterval = 0

        func flush() {
            if !current.isEmpty {
                lines.append(TranscriptSegment(time: start, text: current.joined(separator: " ")))
                current = []
            }
        }

        for word in words {
            if current.isEmpty {
                start = word.timestamp
            } else if word.timestamp - lastEnd > 1.0 || current.count >= 14 {
                flush()
                start = word.timestamp
            }
            current.append(word.substring)
            lastEnd = word.timestamp + word.duration
        }
        flush()
        return lines
    }
}
