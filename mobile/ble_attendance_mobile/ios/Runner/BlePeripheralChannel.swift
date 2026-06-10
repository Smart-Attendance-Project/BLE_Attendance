// BlePeripheralChannel.swift
// Native iOS BLE Peripheral implementation using CoreBluetooth.
// Advertises service data (CBAdvertisementDataServiceDataKey) which is visible
// to other iOS and Android scanners, unlike manufacturer data which iOS strips.

import CoreBluetooth
import Flutter
import UIKit

class BlePeripheralChannel: NSObject, CBPeripheralManagerDelegate {
  static let channelName = "ble_attendance/peripheral"

  private var peripheralManager: CBPeripheralManager?
  private var pendingAdvertiseData: [String: Any]?
  private var isAdvertising = false

  // The Flutter method channel
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: BlePeripheralChannel.channelName, binaryMessenger: messenger)
    super.init()
    peripheralManager = CBPeripheralManager(
      delegate: self,
      queue: DispatchQueue(label: "ble.peripheral.queue"),
      options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
    )
    channel.setMethodCallHandler(handleMethodCall)
  }

  private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startAdvertising":
      guard let args = call.arguments as? [String: Any],
            let serviceUuidStr = args["serviceUuid"] as? String,
            let payloadBytes = args["payload"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGS", message: "serviceUuid and payload required", details: nil))
        return
      }
      startAdvertising(serviceUuidStr: serviceUuidStr, payload: payloadBytes.data)
      result(nil)

    case "stopAdvertising":
      stopAdvertising()
      result(nil)

    case "isAdvertising":
      result(isAdvertising)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startAdvertising(serviceUuidStr: String, payload: Data) {
    // Stop current advertising if active
    if peripheralManager?.isAdvertising == true {
      peripheralManager?.stopAdvertising()
    }
    isAdvertising = false

    let serviceUuid = CBUUID(string: serviceUuidStr)
    let advertiseData: [String: Any] = [
      CBAdvertisementDataServiceUUIDsKey: [serviceUuid],
      CBAdvertisementDataServiceDataKey: [serviceUuid: payload],
      // localName is limited to 8 bytes on iOS — omit to save space for payload
    ]

    pendingAdvertiseData = advertiseData

    if peripheralManager?.state == .poweredOn {
      peripheralManager?.startAdvertising(advertiseData)
    }
    // If not powered on yet, pendingAdvertiseData will be used in
    // peripheralManagerDidUpdateState once state becomes poweredOn
  }

  private func stopAdvertising() {
    peripheralManager?.stopAdvertising()
    isAdvertising = false
    pendingAdvertiseData = nil
  }

  // MARK: - CBPeripheralManagerDelegate

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state == .poweredOn, let data = pendingAdvertiseData {
      peripheral.startAdvertising(data)
    } else if peripheral.state != .poweredOn {
      isAdvertising = false
    }
  }

  func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    if error == nil {
      isAdvertising = true
    } else {
      isAdvertising = false
      // Post error back to Flutter if needed
      channel.invokeMethod("onError", arguments: error?.localizedDescription ?? "unknown error")
    }
  }
}
