import SwiftUI

/// SwiftUI view for the streaming transcription preview overlay.
/// Text is grey while streaming (partial), turns solid white when recording stops (finalized).
struct TranscriptionPreviewView: View {
    @ObservedObject var streamingService = StreamingTranscriptionService.shared

    private var isListening: Bool {
        streamingService.partialTranscription.isEmpty
    }

    /// Build styled text with confirmed (white) and pending (grey) parts
    private var styledText: Text {
        if isListening {
            return Text("Listening...")
                .foregroundColor(.white.opacity(0.4))
        }

        let fullText = streamingService.partialTranscription

        // When streaming stopped, all text is solid white
        guard streamingService.isStreaming else {
            return Text(fullText)
                .foregroundColor(.white.opacity(0.95))
        }

        // Split at confirmed word boundary
        let words = fullText.split(separator: " ", omittingEmptySubsequences: true)
        let confirmedCount = min(streamingService.confirmedWordCount, words.count)

        if confirmedCount == 0 {
            // No confirmed words yet — all pending
            return Text(fullText)
                .foregroundColor(.white.opacity(0.5))
        }

        let confirmedPart = words.prefix(confirmedCount).joined(separator: " ")
        let pendingWords = words.dropFirst(confirmedCount)

        if pendingWords.isEmpty {
            // All words confirmed
            return Text(confirmedPart)
                .foregroundColor(.white.opacity(0.95))
        }

        let pendingPart = pendingWords.joined(separator: " ")
        return Text(confirmedPart + " ")
            .foregroundColor(.white.opacity(0.95))
            + Text(pendingPart)
            .foregroundColor(.white.opacity(0.5))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                styledText
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .id("bottom")
            }
            .onChange(of: streamingService.partialTranscription) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
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
    }
}
