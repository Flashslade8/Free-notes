import SwiftUI
import PencilKit

/// What was drawn on a page, and when in the recording each stroke was written.
private struct PlaybackEntry {
    let strokes: [PKStroke]
    let offsets: [TimeInterval?]
}

private enum PlaybackCache {
    static var entries: [String: PlaybackEntry] = [:]
    static let images = NSCache<NSString, UIImage>()

    static func entry(for page: NotePage, recording: NoteRecording) -> PlaybackEntry {
        let key = "\(page.id)-\(page.drawingData.count)-\(recording.id)-\(recording.trim)-\(recording.duration)"
        if let hit = entries[key] { return hit }
        let strokes = ((try? PKDrawing(data: page.drawingData)) ?? PKDrawing()).strokes
        let offsets = strokes.map { recording.offset(for: $0.path.creationDate) }
        if entries.count > 40 { entries.removeAll() }
        let entry = PlaybackEntry(strokes: strokes, offsets: offsets)
        entries[key] = entry
        return entry
    }
}

/// During playback, the page fills in as the audio reaches each moment you wrote something.
/// Writing that comes later in the recording shows faintly, so you can see what is coming.
struct PlaybackInkLayer: View {
    let page: NotePage
    let recording: NoteRecording
    @ObservedObject var player: AudioPlayerController
    let zoom: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: !player.isPlaying)) { _ in
            layers(at: player.currentTime)
        }
        .allowsHitTesting(false)
    }

    private func layers(at time: TimeInterval) -> some View {
        let entry = PlaybackCache.entry(for: page, recording: recording)
        let visible: Int = entry.offsets.filter { ($0 ?? 0) <= time }.count
        let scale: Int = zoom > 1.5 ? 3 : (zoom > 0.75 ? 2 : 1)
        let solid = image(entry, visible: visible, scale: scale, future: false, time: time)
        let ghost = image(entry, visible: visible, scale: scale, future: true, time: time)

        return ZStack {
            if let ghost {
                Image(uiImage: ghost).resizable().opacity(0.16)
            }
            if let solid {
                Image(uiImage: solid).resizable()
            }
        }
        .frame(width: PageMetrics.size.width * zoom, height: PageMetrics.size.height * zoom)
    }

    /// Drawing the ink to a picture is slow, so each picture is made once and remembered.
    private func image(_ entry: PlaybackEntry, visible: Int, scale: Int,
                       future: Bool, time: TimeInterval) -> UIImage? {
        let key = "\(page.id)-\(page.drawingData.count)-\(recording.id)-\(visible)-\(scale)-\(future)" as NSString
        if let hit = PlaybackCache.images.object(forKey: key) { return hit }

        var chosen: [PKStroke] = []
        for (stroke, offset) in zip(entry.strokes, entry.offsets) {
            let isFuture = (offset ?? 0) > time
            if isFuture == future { chosen.append(stroke) }
        }
        guard !chosen.isEmpty else { return nil }

        let rect = CGRect(origin: .zero, size: PageMetrics.size)
        let picture = lightImage(of: PKDrawing(strokes: chosen), in: rect, scale: CGFloat(scale))
        PlaybackCache.images.setObject(picture, forKey: key)
        return picture
    }
}
