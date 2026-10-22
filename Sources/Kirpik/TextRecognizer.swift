import CoreGraphics
import Vision

/// On-device OCR with the Vision framework. Nothing leaves the Mac.
enum TextRecognizer {
    private static let preferredLanguages = ["tr-TR", "en-US"]

    static func recognize(_ image: CGImage) async -> String {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let supported = try? request.supportedRecognitionLanguages() {
                let languages = preferredLanguages.filter(supported.contains)
                if !languages.isEmpty { request.recognitionLanguages = languages }
            }
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}
