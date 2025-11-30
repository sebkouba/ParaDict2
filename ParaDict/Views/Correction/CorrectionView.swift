import SwiftUI
import AppKit

struct CorrectionView: View {
    let originalTranscription: String
    let llmOutput: String
    let onSubmit: (String, String?) -> Void
    let onCancel: () -> Void

    @State private var correctedText: String
    @State private var explanation: String = ""
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case correction
        case explanation
    }

    /// Whether LLM enhancement was used (transcription differs from pasted output)
    private var wasEnhanced: Bool {
        originalTranscription != llmOutput
    }

    init(originalTranscription: String, llmOutput: String, onSubmit: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
        self.originalTranscription = originalTranscription
        self.llmOutput = llmOutput
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self._correctedText = State(initialValue: llmOutput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Correction")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Original transcription:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(originalTranscription)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }

            if wasEnhanced {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LLM changes:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    DiffView(original: originalTranscription, modified: llmOutput)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Corrected:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                AutoSizingTextEditor(
                    text: $correctedText,
                    isFocused: focusedField == .correction,
                    onTab: { focusedField = .explanation }
                )
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .focused($focusedField, equals: .correction)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Explanation (optional):")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Why was this correction needed?", text: $explanation)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .explanation)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Save Correction") {
                    let explanationValue = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSubmit(correctedText, explanationValue.isEmpty ? nil : explanationValue)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            focusedField = .correction
        }
    }
}

// MARK: - Auto-Sizing Text Editor

struct AutoSizingTextEditor: View {
    @Binding var text: String
    var isFocused: Bool
    var onTab: () -> Void

    @State private var textHeight: CGFloat = 60

    private let minHeight: CGFloat = 60

    var body: some View {
        AutoSizingTextEditorRepresentable(
            text: $text,
            textHeight: $textHeight,
            isFocused: isFocused,
            onTab: onTab,
            minHeight: minHeight
        )
        .frame(height: max(minHeight, textHeight))
    }
}

struct AutoSizingTextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var textHeight: CGFloat
    var isFocused: Bool
    var onTab: () -> Void
    let minHeight: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        context.coordinator.onTab = onTab
        context.coordinator.textHeight = $textHeight
        context.coordinator.minHeight = minHeight

        // Update height after layout
        DispatchQueue.main.async {
            context.coordinator.updateHeight()
        }

        if isFocused && textView.window?.firstResponder != textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, textHeight: $textHeight, onTab: onTab, minHeight: minHeight)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var textHeight: Binding<CGFloat>
        var onTab: () -> Void
        var textView: NSTextView?
        var minHeight: CGFloat

        init(text: Binding<String>, textHeight: Binding<CGFloat>, onTab: @escaping () -> Void, minHeight: CGFloat) {
            self.text = text
            self.textHeight = textHeight
            self.onTab = onTab
            self.minHeight = minHeight
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            updateHeight()
        }

        func updateHeight() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = layoutManager.usedRect(for: textContainer).height
            let newHeight = max(minHeight, contentHeight + textView.textContainerInset.height * 2 + 8)

            if abs(textHeight.wrappedValue - newHeight) > 1 {
                textHeight.wrappedValue = newHeight
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                onTab()
                return true
            }
            return false
        }
    }
}

// MARK: - Diff View

struct DiffView: View {
    let original: String
    let modified: String

    var body: some View {
        Text(attributedDiff)
            .textSelection(.enabled)
    }

    private var attributedDiff: AttributedString {
        let originalWords = tokenize(original)
        let modifiedWords = tokenize(modified)

        // Compute LCS-based inline diff
        let diffOps = computeInlineDiff(from: originalWords, to: modifiedWords)

        var result = AttributedString()

        for (index, op) in diffOps.enumerated() {
            switch op {
            case .equal(let word):
                result.append(AttributedString(word))

            case .delete(let word):
                var attr = AttributedString(word)
                attr.foregroundColor = .red
                attr.strikethroughStyle = .single
                result.append(attr)

            case .insert(let word):
                var attr = AttributedString(word)
                attr.foregroundColor = .green
                attr.backgroundColor = Color.green.opacity(0.1)
                result.append(attr)
            }

            // Add space after each word except the last
            if index < diffOps.count - 1 {
                result.append(AttributedString(" "))
            }
        }

        return result
    }

    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    private enum DiffOp {
        case equal(String)
        case delete(String)
        case insert(String)
    }

    /// Compute inline diff operations using longest common subsequence
    private func computeInlineDiff(from original: [String], to modified: [String]) -> [DiffOp] {
        let lcs = longestCommonSubsequence(original, modified)
        var result: [DiffOp] = []

        var i = 0  // index in original
        var j = 0  // index in modified
        var k = 0  // index in lcs

        while i < original.count || j < modified.count {
            if k < lcs.count {
                // Delete words from original until we hit the next LCS word
                while i < original.count && original[i] != lcs[k] {
                    result.append(.delete(original[i]))
                    i += 1
                }

                // Insert words from modified until we hit the next LCS word
                while j < modified.count && modified[j] != lcs[k] {
                    result.append(.insert(modified[j]))
                    j += 1
                }

                // This word is in both - it's equal
                if i < original.count && j < modified.count {
                    result.append(.equal(lcs[k]))
                    i += 1
                    j += 1
                    k += 1
                }
            } else {
                // No more LCS words - remaining original words are deletions
                while i < original.count {
                    result.append(.delete(original[i]))
                    i += 1
                }

                // Remaining modified words are insertions
                while j < modified.count {
                    result.append(.insert(modified[j]))
                    j += 1
                }
            }
        }

        return result
    }

    /// Compute the longest common subsequence of two arrays
    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count
        let n = b.count

        // Build LCS length table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find the LCS
        var lcs: [String] = []
        var i = m, j = n

        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                lcs.append(a[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return lcs.reversed()
    }
}
