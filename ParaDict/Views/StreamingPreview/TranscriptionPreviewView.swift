import SwiftUI

/// SwiftUI view for the streaming transcription preview overlay.
/// Observes StreamingTranscriptionService for partial transcription updates.
struct TranscriptionPreviewView: View {
    @ObservedObject var streamingService = StreamingTranscriptionService.shared
    let charLimit: Int

    private var displayText: String {
        let text = streamingService.partialTranscription
        if text.isEmpty {
            return "Listening..."
        }
        // Truncate from the beginning if over the character limit (show most recent text)
        if text.count > charLimit {
            let startIndex = text.index(text.endIndex, offsetBy: -charLimit)
            return "..." + text[startIndex...]
        }
        return text
    }

    private var isListening: Bool {
        streamingService.partialTranscription.isEmpty
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isListening ? .white.opacity(0.5) : .white.opacity(0.85))
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Color.black.opacity(0.85)
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .opacity(0.05)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .animation(.easeInOut(duration: 0.15), value: streamingService.partialTranscription)
    }
}
