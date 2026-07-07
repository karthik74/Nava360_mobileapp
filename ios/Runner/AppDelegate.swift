import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// Hidden secure text field whose layer hosts the window's content while
  /// protection is on — iOS excludes secure-entry content from screenshots and
  /// screen recordings, so captures of the app come out black (the same
  /// technique WhatsApp-class apps use).
  private var secureField: UITextField?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Same channel the Android side exposes; the Dart SecureScreen helper is
    // platform-agnostic and just calls enable/disable.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "app.secure_screen") {
      let channel = FlutterMethodChannel(
        name: "app/secure_screen", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "enable":
          self?.setSecure(true)
          result(true)
        case "disable":
          self?.setSecure(false)
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private func setSecure(_ enabled: Bool) {
    DispatchQueue.main.async {
      guard let window = self.appKeyWindow() else { return }
      if self.secureField == nil {
        if !enabled { return }
        let field = UITextField()
        field.isUserInteractionEnabled = false
        window.addSubview(field)
        // Re-parent the window's layer inside the secure field's canvas layer:
        // while isSecureTextEntry is true, the OS blanks that content in any
        // capture but renders it normally on the live screen.
        window.layer.superlayer?.addSublayer(field.layer)
        if #available(iOS 17.0, *) {
          field.layer.sublayers?.last?.addSublayer(window.layer)
        } else {
          field.layer.sublayers?.first?.addSublayer(window.layer)
        }
        self.secureField = field
      }
      self.secureField?.isSecureTextEntry = enabled
    }
  }

  /// The scene-managed key window (SceneDelegate template — AppDelegate.window
  /// is nil), with a fallback to any window of the first connected scene.
  private func appKeyWindow() -> UIWindow? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return windows.first { $0.isKeyWindow } ?? windows.first
  }
}
