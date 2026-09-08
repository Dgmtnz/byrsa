// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import Accelerate
import CoreImage
import Foundation
import UIKit

/// Focus and exposure measures, and the perspective warp.
///
/// UNVERIFIED: never compiled or run. See `UNVERIFIED.md`.
enum ImageOps {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Relative focus measure, 0...1, comparable only within one scene.
    ///
    /// Mirrors the Android implementation on purpose: auto-capture must not
    /// fire at different moments on the two platforms for the same scene.
    static func sharpness(_ buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        let step = max(1, width / 160)
        var total = 0.0
        var count = 0
        var y = step
        while y < height - step {
            var x = step
            while x < width - step {
                let centre = Int(pixels[y * stride + x]) * 4
                let neighbours = Int(pixels[y * stride + x - step])
                    + Int(pixels[y * stride + x + step])
                    + Int(pixels[(y - step) * stride + x])
                    + Int(pixels[(y + step) * stride + x])
                total += Double(abs(centre - neighbours))
                count += 1
                x += step
            }
            y += step
        }
        guard count > 0 else { return 0 }
        return min(1, max(0, (total / Double(count)) / 40.0))
    }

    /// Mean luma, 0...1.
    static func brightness(_ buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        let step = max(1, width / 120)
        var total = 0
        var count = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                total += Int(pixels[y * stride + x])
                count += 1
                x += step
            }
            y += step
        }
        return count == 0 ? 0 : Double(total) / Double(count) / 255.0
    }

    /// Warps the quadrilateral `corners` of `image` into an upright rectangle.
    ///
    /// `CIPerspectiveCorrection` is Core Image's own four-point transform, the
    /// counterpart of `Matrix.setPolyToPoly` on Android. Both platforms use the
    /// system's resampler rather than a homography we would have to test twice.
    ///
    /// - Parameter corners: eight values, TL, TR, BR, BL, normalised, y-down.
    static func warp(
        image: UIImage,
        corners: [CGFloat],
        targetAspectRatio: Double?
    ) -> UIImage? {
        guard corners.count == 8, let input = CIImage(image: image) else { return nil }
        let size = input.extent.size

        // Core Image works y-up, the wire format is y-down.
        func point(_ index: Int) -> CGPoint {
            CGPoint(
                x: corners[index * 2] * size.width,
                y: (1 - corners[index * 2 + 1]) * size.height
            )
        }

        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: point(0)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: point(1)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: point(2)), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: point(3)), forKey: "inputBottomLeft")

        guard var output = filter.outputImage else { return nil }

        if let ratio = targetAspectRatio, ratio > 0 {
            let target = CGSize(width: output.extent.width, height: output.extent.width / ratio)
            output = output.transformed(
                by: CGAffineTransform(scaleX: 1, y: target.height / output.extent.height)
            )
        }
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
