// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import Flutter
import UIKit

/// iOS side of `byrsa_capture`.
///
/// UNVERIFIED: never compiled. See `UNVERIFIED.md`, row U-01. The file exists
/// and is kept in the build because a missing platform is invisible debt, while
/// a platform that fails to build is information.
public class ByrsaCapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var session: CaptureSession?
    private var eventSink: FlutterEventSink?
    private let registry: FlutterTextureRegistry

    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ByrsaCapturePlugin(registry: registrar.textures())
        let methods = FlutterMethodChannel(
            name: "dev.byrsa/capture", binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methods)

        let events = FlutterEventChannel(
            name: "dev.byrsa/capture/detections", binaryMessenger: registrar.messenger()
        )
        events.setStreamHandler(instance)
    }

    public func onListen(
        withArguments arguments: Any?, eventSink: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "isSupported":
            result(AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back
            ) != nil)

        case "start":
            do {
                let session = self.session ?? CaptureSession(registry: registry)
                self.session = session
                let textureId = try session.start(
                    detectionsPerSecond: arguments["detectionsPerSecond"] as? Int ?? 8,
                    torch: arguments["torch"] as? Bool ?? false,
                    sink: { [weak self] payload in self?.eventSink?(payload) }
                )
                result(Int(textureId))
            } catch {
                result(FlutterError(
                    code: "start-failed", message: error.localizedDescription, details: nil
                ))
            }

        case "stop":
            session?.stop()
            result(nil)

        case "capture":
            guard let session else {
                result(FlutterError(
                    code: "not-started", message: "The camera session is not running.", details: nil
                ))
                return
            }
            session.capture(
                rectifyOnCapture: arguments["rectifyOnCapture"] as? Bool ?? true
            ) { outcome in
                switch outcome {
                case .success(let payload):
                    result(payload)
                case .failure(let error):
                    result(FlutterError(
                        code: "capture-failed",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }

        case "rectify":
            guard let path = arguments["imagePath"] as? String,
                  let quad = arguments["quad"] as? [[String: Any]] else {
                result(FlutterError(code: "bad-arguments", message: "rectify needs imagePath and quad", details: nil))
                return
            }
            do {
                let session = self.session ?? CaptureSession(registry: registry)
                result(try session.rectify(
                    imagePath: path,
                    corners: Self.corners(from: quad),
                    targetAspectRatio: arguments["targetAspectRatio"] as? Double
                ))
            } catch {
                result(FlutterError(
                    code: "rectify-failed", message: error.localizedDescription, details: nil
                ))
            }

        case "setTorch":
            session?.setTorch(on: arguments["on"] as? Bool ?? false)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func corners(from quad: [[String: Any]]) -> [CGFloat] {
        quad.flatMap { point -> [CGFloat] in
            [
                CGFloat((point["x"] as? NSNumber)?.doubleValue ?? 0),
                CGFloat((point["y"] as? NSNumber)?.doubleValue ?? 0),
            ]
        }
    }
}
