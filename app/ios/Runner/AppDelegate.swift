import Flutter
import UIKit

/// The application's own platform channel, for the one thing Dart is bad at.
///
/// Encoding a JPEG in pure Dart costs about 900 ms for a 6.8 MP page. The
/// platform encoder does it in a fraction of that and is already on every
/// device.
///
/// UNVERIFIED: never compiled. There is no macOS machine in the project. The
/// Dart side falls back to its own encoder when this channel is unavailable or
/// fails, so a mistake here costs speed rather than the scan.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "dev.byrsa/codec",
      binaryMessenger: engineBridge.applicationBinaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "encodeJpeg" else {
        result(FlutterMethodNotImplemented)
        return
      }
      Self.encodeJpeg(call.arguments as? [String: Any] ?? [:], result)
    }
  }

  /// Encodes interleaved 8-bit RGB into a JPEG file.
  ///
  /// Three channels, never one: a grayscale page is expanded on the Dart side,
  /// because a single-channel buffer produces a three-component JPEG anyway and
  /// a file twice the size.
  private static func encodeJpeg(
    _ arguments: [String: Any],
    _ result: @escaping FlutterResult
  ) {
    guard let data = arguments["rgb"] as? FlutterStandardTypedData,
          let width = arguments["width"] as? Int,
          let height = arguments["height"] as? Int,
          let path = arguments["path"] as? String else {
      result(FlutterError(
        code: "bad-arguments",
        message: "encodeJpeg needs rgb, width, height and path.",
        details: nil
      ))
      return
    }
    let quality = arguments["quality"] as? Int ?? 92
    let expected = width * height * 3
    guard data.data.count >= expected else {
      result(FlutterError(
        code: "bad-arguments",
        message: "Expected \(expected) bytes for \(width)x\(height), got \(data.data.count).",
        details: nil
      ))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      guard let provider = CGDataProvider(data: data.data as CFData),
            let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 24,
              bytesPerRow: width * 3,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
            ),
            let jpeg = UIImage(cgImage: image)
              .jpegData(compressionQuality: CGFloat(quality) / 100.0)
      else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "encode-failed",
            message: "The platform encoder refused the image.",
            details: nil
          ))
        }
        return
      }

      do {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try jpeg.write(to: url)
        DispatchQueue.main.async { result(path) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "encode-failed",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }
}
