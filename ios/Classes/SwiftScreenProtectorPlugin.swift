import Flutter
import UIKit
import ScreenProtectorKit

enum ScrennProtectorMethod: String {
    case protectDataLeakageWithBlur
    case protectDataLeakageWithBlurOff
    case protectDataLeakageWithImage
    case protectDataLeakageWithImageOff
    case protectDataLeakageWithColor
    case protectDataLeakageWithColorOff
    case protectDataLeakageOff
    case preventScreenshotOn
    case preventScreenshotOff
    case preventScreenRecordOn
    case preventScreenRecordOff
    case addListener
    case removeListener
    case isRecording
}

public class SwiftScreenProtectorPlugin: NSObject, FlutterPlugin {
    private static var channel: FlutterMethodChannel? = nil
    private let protectKit: ScreenProtectorKit
    private var protectMode: ScreenProtectorMode = .none
    private var isPreventScreenshotEnabled = false

    init(_ screenProtector: ScreenProtectorKit) {
        self.protectKit = screenProtector
    }
    
    private func initializeManagerIfNeeded(forceRecreate: Bool = false) {
        if Thread.isMainThread == false {
            DispatchQueue.main.async { [weak self] in
                self?.initializeManagerIfNeeded(forceRecreate: forceRecreate)
            }
            return
        }

        let currentWindow = Self.activeWindow()

        // 修复: 只有在窗口真正变化时才重建，避免频繁前后台切换导致黑屏
        let windowChanged = trackedWindow != nil && currentWindow !== trackedWindow && currentWindow != nil
        if forceRecreate && windowChanged {
            self.didBecomeActive(.dataLeakage)
            tearDownManager()
        }

        guard screenProtectorKit == nil else { return }
        guard let window = currentWindow else {
            self.log()
            // Disable data leakage protection when no active UIWindow is available
            // 修复: 移除此处的 didBecomeActive 调用，避免状态混乱
            print("[screen_protector] Active UIWindow is not available.")
            return
        }

        self.screenProtectorKit = ScreenProtectorKit(window: window)
        onMain { self.screenProtectorKit?.configurePreventionScreenshot() }
        onMain { self.addListenerIfNeeded() }

        self.trackedWindow = window
    }
    

    public static func register(with registrar: FlutterPluginRegistrar) {
        SwiftScreenProtectorPlugin.channel = FlutterMethodChannel(name: "screen_protector", binaryMessenger: registrar.messenger())

        let kit = ScreenProtectorKit(window: SwiftScreenProtectorPlugin.keyWindow())
        kit.setRootViewResolver(FlutterRootViewResolver())
        ScreenProtectorKit.initial(with: kit.window?.rootViewController?.view)
        let instance = SwiftScreenProtectorPlugin(kit)
        
        registrar.addMethodCallDelegate(instance, channel: SwiftScreenProtectorPlugin.channel!)
        registrar.addApplicationDelegate(instance)
    }
    
    public func willResignActive(_ type: ProtectionType) {
        if type == .dataLeakage {
            // Protect Data Leakage - ON
            if colorProtectionState == .on {
                onMain { self.screenProtectorKit?.enabledColorScreen(hexColor: self.colorProtectionHex) }
            } else if imageProtectionState == .on {
                onMain { self.screenProtectorKit?.enabledImageScreen(named: self.imageProtectionName) }
            } else if blurProtectionState == .on {
                onMain { self.screenProtectorKit?.enabledBlurScreen() }
            }
        }
        
        if type == .screenshot {
            // Prevent Screenshot - OFF
            if preventScreenshotState == .off {
                onMain { self.screenProtectorKit?.disablePreventScreenshot() }
            }
        }
    }
    
    public func didBecomeActive(_ type: ProtectionType) {
        if type == .dataLeakage {
            // Protect Data Leakage - OFF
            if colorProtectionState == .on {
                onMain { self.screenProtectorKit?.disableColorScreen() }
            } else if imageProtectionState == .on {
                onMain { self.screenProtectorKit?.disableImageScreen() }
            } else if blurProtectionState == .on {
                onMain { self.screenProtectorKit?.disableBlurScreen() }
            }
        }
        
        if type == .screenshot {
            // Prevent Screenshot - ON
            if preventScreenshotState == .on {
                onMain { self.screenProtectorKit?.enabledPreventScreenshot() }
            }
        }
    }
    
    @objc func onSceneDidBecomeActive(_ notification: Notification) {
        // Protect Data Leakage - OFF && Prevent Screenshot - ON
        DispatchQueue.main.async {
            // 修复: 不再强制重建，只在必要时初始化
            self.initializeManagerIfNeeded(forceRecreate: false)
            self.didBecomeActive(.dataLeakage)
            self.didBecomeActive(.screenshot)
        }
    }
    
    @objc func onSceneWillResignActive(_ notification: Notification) {
        // Protect Data Leakage - ON && Prevent Screenshot - OFF
        DispatchQueue.main.async {
            self.initializeManagerIfNeeded()
            self.willResignActive(.dataLeakage)
            self.willResignActive(.screenshot)
        }
    }
    

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if Thread.isMainThread {
            handleFunc(call, result: result)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.handleFunc(call, result: result)
        }
    }
    
    public func applicationWillResignActive(_ application: UIApplication) {
        updateWindowIfNeeded()
        applyDataLeakageProtection()
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
        updateWindowIfNeeded()
        clearDataLeakageProtection()
    }
    
    private func observeSceneLifecycle() {
        guard #available(iOS 13.0, *) else { return }
        let center = NotificationCenter.default
        
        let disconnectObserver = center.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] notification in
            guard let scene = notification.object as? UIWindowScene,
                  let trackedScene = self?.trackedWindow?.windowScene,
                  trackedScene == scene else { return }
            self?.tearDownManager()
        }
        
        let foregroundObserver = center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in
            // 修复: 不再强制重建，只在必要时初始化
            self?.initializeManagerIfNeeded(forceRecreate: false)
        }
        
        sceneObservers.append(contentsOf: [disconnectObserver, foregroundObserver])
    }
    
    private func tearDownManager() {
        onMain { self.screenProtectorKit?.removeAllObserver() }
        screenProtectorKit = nil
        trackedWindow = nil
    }
    
    private static func activeWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.windows.first { $0.isKeyWindow }
        }
    }
    
    private func log() {
        #if DEBUG
        print("[screen_protector] screenProtectorKit: \(String(describing: screenProtectorKit))")
        print("[screen_protector] trackedWindow: \(String(describing: trackedWindow))")
        print("[screen_protector] sceneObservers: \(sceneObservers)")
        print("[screen_protector] preventScreenshotState: \(preventScreenshotState)")
        print("[screen_protector] blurProtectionState: \(blurProtectionState)")
        print("[screen_protector] imageProtectionState: \(imageProtectionState)")
        print("[screen_protector] colorProtectionState: \(colorProtectionState)")
        print("[screen_protector] imageProtectionName: \(imageProtectionName)")
        print("[screen_protector] colorProtectionHex: \(colorProtectionHex)")
        print("[screen_protector] needAddListener: \(needAddListener)")
        #endif
    }
    

    deinit {
        updateWindowIfNeeded()
        protectKit.removeAllObserver()
        protectKit.disablePreventScreenshot()
        protectKit.disablePreventScreenRecording()
        clearDataLeakageProtection()
    }
}

private extension SwiftScreenProtectorPlugin {
    func handleFunc(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? Dictionary<String, String>

        switch ScrennProtectorMethod(rawValue: call.method) {
        case .protectDataLeakageWithBlur:
            setDataLeakageProtectMode(.blur)
            result(true)
            break
        case .protectDataLeakageWithBlurOff:
            if case .blur = protectMode {
                protectMode = .none
            }
            protectKit.disableBlurScreen()
            result(true)
            break
        case .protectDataLeakageWithImage:
            setDataLeakageProtectMode(.image(name: args?["name"] ?? "LaunchImage"))
            result(true)
            break
        case .protectDataLeakageWithImageOff:
            if case .image = protectMode {
                protectMode = .none
            }
            protectKit.disableImageScreen()
            result(true)
            break
        case .protectDataLeakageWithColor:
            guard let hexColor = args?["hexColor"] else {
                result(false)
                return
            }
            setDataLeakageProtectMode(.color(hex: hexColor))
            result(true)
            break
        case .protectDataLeakageWithColorOff:
            if case .color = protectMode {
                protectMode = .none
            }
            protectKit.disableColorScreen()
            result(true)
            break
        case .protectDataLeakageOff:
            protectMode = .none
            clearDataLeakageProtection()
            result(true)
            break
        case .preventScreenshotOn:
            isPreventScreenshotEnabled = true
            updateWindowIfNeeded()
            protectKit.enabledPreventScreenshot()
            result(true)
            break
        case .preventScreenshotOff:
            isPreventScreenshotEnabled = false
            updateWindowIfNeeded()
            protectKit.disablePreventScreenshot()
            result(true)
            break
        case .preventScreenRecordOn:
            updateWindowIfNeeded()
            protectKit.enabledPreventScreenRecording()
            result(true)
            break
        case .preventScreenRecordOff:
            updateWindowIfNeeded()
            protectKit.disablePreventScreenRecording()
            result(true)
            break
        case .addListener:
            protectKit.screenshotObserver { [weak channel = SwiftScreenProtectorPlugin.channel] in
                channel?.invokeMethod("onScreenshot", arguments: nil)
            }
            if #available(iOS 11.0, *) {
                protectKit.screenRecordObserver { [weak channel = SwiftScreenProtectorPlugin.channel] isCaptured in
                    channel?.invokeMethod("onScreenRecord", arguments: isCaptured)
                }
            }
            result("listened")
            break
        case .removeListener:
            protectKit.removeAllObserver()
            result("removed")
            break
        case .isRecording:
            if #available(iOS 11.0, *) {
                result(protectKit.screenIsRecording())
            } else {
                result(false)
            }
            break
        default:
            result(false)
            break
        }
    }
    
    func updateWindowIfNeeded() {
        if let window = Self.keyWindow() {
            protectKit.window = window
        }
    }

    func applyDataLeakageProtection() {
        updateWindowIfNeeded()
        clearDataLeakageProtection()
        switch protectMode {
        case .blur:
            protectKit.enabledBlurScreen()
        case let .image(name):
            protectKit.enabledImageScreen(named: name)
        case let .color(hex):
            protectKit.enabledColorScreen(hexColor: hex)
        case .none:
            break
        }
    }

    func clearDataLeakageProtection() {
        protectKit.disableBlurScreen()
        protectKit.disableImageScreen()
        protectKit.disableColorScreen()
    }

    func setDataLeakageProtectMode(_ mode: ScreenProtectorMode) {
        protectMode = mode
        if UIApplication.shared.applicationState != .active {
            applyDataLeakageProtection()
        } else {
            clearDataLeakageProtection()
        }
    }

    static func keyWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }
        return UIApplication.shared.keyWindow
    }
}
