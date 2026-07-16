import CoreGraphics
import Foundation
@preconcurrency import Vision

enum OCRService {
    static func recognize(image: CGImage, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                completion(.success(lines.joined(separator: "\n")))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

            do {
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
}
