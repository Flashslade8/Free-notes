import SwiftUI
import AVFoundation
import PencilKit

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
struct NoteRecording: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval      // length of the audio itself (pauses not included)
    var pauses: [RecordingPause] = []
    var markers: [RecordingMarker] = []

    var fileURL: URL { RecordingFiles.url(for: id) }
    var hasAudio: Bool { RecordingFiles.exists(id) }

    /// Where in the audio something written at `date` belongs, or nil if the
    /// recording wasn't running then. Time spent paused is taken out.
    func offset(for date: Date) -> TimeInterval? {
        guard date >= startedAt, date <= endedAt else { return nil }
        var paused: TimeInterval = 0
        for pause in pauses.sorted(by: { $0.start < $1.start }) {
            if date >= pause.end {
                paused += pause.end.timeIntervalSince(pause.start)
            } else if date > pause.start {
                return max(0, pause.start.timeIntervalSince(startedAt) - paused)
            }
        }
        return max(0, date.timeIntervalSince(startedAt) - paused)
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
