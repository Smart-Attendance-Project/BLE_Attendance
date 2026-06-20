import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // Keep a strong reference so the channel and CBPeripheralManager stay alive.
  private var blePeripheralChannel: BlePeripheralChannel?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      blePeripheralChannel = BlePeripheralChannel(messenger: controller.binaryMessenger)
    }
  }
}
