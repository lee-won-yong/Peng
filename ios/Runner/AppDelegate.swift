import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let databaseQueue = DispatchQueue(label: "peng.database")
  private var database: LearningSQLite?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PengDatabase") else { return }
    let channel = FlutterMethodChannel(name: "peng/database", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      self.databaseQueue.async {
        do {
          if self.database == nil {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            self.database = try LearningSQLite(path: directory.appendingPathComponent("peng.sqlite").path)
          }
          guard let database = self.database else { throw NSError(domain: "PengSQLite", code: 5) }
          let value: Any?
          switch call.method {
          case "path": value = database.path
          case "batch":
            guard let statements = call.arguments as? [[String: Any]] else { throw NSError(domain: "PengSQLite", code: 6) }
            try database.batch(statements)
            value = nil
          case "query":
            guard let statement = call.arguments as? [String: Any], let sql = statement["sql"] as? String else { throw NSError(domain: "PengSQLite", code: 7) }
            value = try database.execute(sql, args: statement["args"] as? [Any] ?? [])
          default:
            DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
            return
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "sqlite", message: "학습 데이터 저장소 작업에 실패했어요.", details: nil)) }
        }
      }
    }
  }
}
