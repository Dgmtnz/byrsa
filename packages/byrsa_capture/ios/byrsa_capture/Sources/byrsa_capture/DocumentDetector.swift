// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import CoreImage
import Foundation
import Vision

/// Finds the corners of a page in a camera frame using Apple's Vision
/// framework.
///
/// Vision is part of the system, costs nothing in binary size, and is better at
/// this than anything we would write. It is also the one place where iOS gets
/// something Android does not have an equivalent for without Play Services,
/// which is exactly why the Android side has its own detector.
///
/// UNVERIFIED: no line of this file has ever run. There is no macOS machine in
/// the project. See `UNVERIFIED.md`, rows U-01 and U-07.
enum DocumentDetector {

    /// Corners in normalised, y-down coordinates, ordered TL, TR, BR, BL.
    struct Quad {
        let points: [CGPoint]
    }

    static func detect(in buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Quad? {
        if #available(iOS 15.0, *), let quad = detectSegmentation(buffer, orientation) {
            return quad
        }
        return detectRectangles(buffer, orientation)
    }

    /// The good path: a segmentation model that finds a page even against a
    /// low-contrast background.
    @available(iOS 15.0, *)
    private static func detectSegmentation(
        _ buffer: CVPixelBuffer,
        _ orientation: CGImagePropertyOrientation
    ) -> Quad? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        return quad(from: observation)
    }

    /// The fallback: classical rectangle detection, tuned for a page that
    /// roughly fills the frame — the same assumption the Android detector makes,
    /// so the two platforms fail in the same situations rather than in
    /// different ones.
    private static func detectRectangles(
        _ buffer: CVPixelBuffer,
        _ orientation: CGImagePropertyOrientation
    ) -> Quad? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.35
        request.minimumConfidence = 0.6
        request.maximumObservations = 1
        request.quadratureTolerance = 30

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        return quad(from: observation)
    }

    /// Vision reports corners in a y-up unit square; the shared Dart contract is
    /// y-down. Getting this flip wrong is how an overlay ends up mirrored.
    private static func quad(from observation: VNRectangleObservation) -> Quad {
        func flip(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: 1 - point.y)
        }
        return Quad(points: [
            flip(observation.topLeft),
            flip(observation.topRight),
            flip(observation.bottomRight),
            flip(observation.bottomLeft),
        ])
    }
}
