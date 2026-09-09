// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import Flutter
import Foundation
import UIKit

/// One AVFoundation session: preview into a Flutter texture, live detection,
/// stills.
///
/// Structurally the twin of the Android `CaptureSession`: frames never cross
/// into Dart, only four corners per detection do, and stability and the
/// user-facing hint are decided in Dart where they are unit-tested.
///
/// UNVERIFIED: never compiled. There is no macOS machine in the project. See
/// `UNVERIFIED.md`, rows U-01 and U-07.
final class CaptureSession: NSObject, FlutterTexture,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCapturePhotoCaptureDelegate {

    typealias DetectionSink = ([String: Any?]) -> Void

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "dev.byrsa.capture")

    private weak var registry: FlutterTextureRegistry?
    private var textureId: Int64 = 0
    private var latestFrame: CVPixelBuffer?
    private var lastQuad: [CGFloat]?
    private var device: AVCaptureDevice?

    private var minimumInterval: TimeInterval = 0.125
    private var lastDetectionAt: TimeInterval = 0
    private var detectionSink: DetectionSink?
    private var rectifyOnCapture = true
    private var pendingCapture: ((Result<[String: Any?], Error>) -> Void)?

    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        super.init()
    }

    // MARK: - Lifecycle

    /// Whether the user has already answered the camera prompt, and how.
    ///
    /// iOS refuses to configure a capture session without this, and unlike
    /// Android it does not merely fail — an app that touches the camera with no
    /// usage description in its Info.plist is terminated.
    static func authorisationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Asks for camera access, returning what the user chose.
    static func requestAuthorisation(_ completion: @escaping (Bool) -> Void) {
        switch authorisationStatus() {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            // Denied or restricted. Asking again does nothing; only Settings
            // will help, and the interface has to say so rather than retry.
            completion(false)
        }
    }

    func start(detectionsPerSecond: Int, torch: Bool, sink: @escaping DetectionSink) throws -> Int64 {
        guard Self.authorisationStatus() == .authorized else {
            throw CaptureError.permissionDenied
        }
        minimumInterval = 1.0 / Double(min(max(detectionsPerSecond, 1), 30))
        detectionSink = sink

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else {
            throw CaptureError.noCamera
        }
        device = camera

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureError.noCamera }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else { throw CaptureError.noCamera }
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else { throw CaptureError.noCamera }
        session.addOutput(photoOutput)

        session.commitConfiguration()

        textureId = registry?.register(self) ?? 0
        queue.async { [weak self] in self?.session.startRunning() }
        if torch { setTorch(on: true) }
        return textureId
    }

    func stop() {
        session.stopRunning()
        if textureId != 0 {
            registry?.unregisterTexture(textureId)
            textureId = 0
        }
        latestFrame = nil
        lastQuad = nil
    }

    func setTorch(on: Bool) {
        guard let device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // MARK: - FlutterTexture

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let frame = latestFrame else { return nil }
        return Unmanaged.passRetained(frame)
    }

    // MARK: - Frames

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestFrame = buffer
        registry?.textureFrameAvailable(textureId)

        let now = CACurrentMediaTime()
        guard now - lastDetectionAt >= minimumInterval else { return }
        lastDetectionAt = now

        let orientation = currentOrientation()
        let quad = DocumentDetector.detect(in: buffer, orientation: orientation)
        let sharpness = ImageOps.sharpness(buffer)
        let brightness = ImageOps.brightness(buffer)

        var corners: [CGFloat]?
        if let quad {
            corners = quad.points.flatMap { [$0.x, $0.y] }
        }
        lastQuad = corners

        let payload: [String: Any?] = [
            "quad": corners.map { pairs in
                stride(from: 0, to: pairs.count, by: 2).map {
                    ["x": Double(pairs[$0]), "y": Double(pairs[$0 + 1])]
                }
            },
            "sharpness": sharpness,
            "brightness": brightness,
            "hint": corners == nil ? "noDocument" : "moving",
        ]
        DispatchQueue.main.async { [weak self] in self?.detectionSink?(payload) }
    }

    private func currentOrientation() -> CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        default: return .right
        }
    }

    // MARK: - Stills

    func capture(
        rectifyOnCapture: Bool,
        completion: @escaping (Result<[String: Any?], Error>) -> Void
    ) {
        self.rectifyOnCapture = rectifyOnCapture
        pendingCapture = completion
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let completion = pendingCapture else { return }
        pendingCapture = nil

        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(.failure(CaptureError.captureFailed))
            return
        }
        do {
            let originalPath = try write(data: data, suffix: "jpg")
            let quad = lastQuad ?? [0, 0, 1, 0, 1, 1, 0, 1]
            var rectifiedPath: String?
            if rectifyOnCapture,
               let warped = ImageOps.warp(image: image, corners: quad, targetAspectRatio: nil),
               let warpedData = warped.jpegData(compressionQuality: 0.92) {
                rectifiedPath = try write(data: warpedData, suffix: "page.jpg")
            }
            completion(.success([
                "originalPath": originalPath,
                "rectifiedPath": rectifiedPath,
                "quad": Self.cornersToList(quad),
                "width": Int(image.size.width * image.scale),
                "height": Int(image.size.height * image.scale),
            ]))
        } catch {
            completion(.failure(error))
        }
    }

    /// Re-warps an existing file. Always from the original, never from a warp.
    func rectify(imagePath: String, corners: [CGFloat], targetAspectRatio: Double?) throws -> String {
        guard let image = UIImage(contentsOfFile: imagePath),
              let warped = ImageOps.warp(
                  image: image, corners: corners, targetAspectRatio: targetAspectRatio
              ),
              let data = warped.jpegData(compressionQuality: 0.92) else {
            throw CaptureError.rectifyFailed
        }
        let path = imagePath + ".page.jpg"
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    private func write(data: Data, suffix: String) throws -> String {
        let name = "byrsa-\(Int(Date().timeIntervalSince1970 * 1000)).\(suffix)"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try data.write(to: url)
        return url.path
    }

    static func cornersToList(_ corners: [CGFloat]) -> [[String: Double]] {
        stride(from: 0, to: corners.count, by: 2).map {
            ["x": Double(corners[$0]), "y": Double(corners[$0 + 1])]
        }
    }

    enum CaptureError: Error, LocalizedError {
        case noCamera
        case captureFailed
        case rectifyFailed
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noCamera: return "No usable back camera on this device."
            case .captureFailed: return "The camera returned no image."
            case .rectifyFailed: return "Could not warp the image."
            case .permissionDenied: return "Byrsa needs the camera to scan a document."
            }
        }
    }
}
