//
//  AppDelegate.swift
//  Voxor
//
//  Created by app on 12/4/2026.
//

import UIKit
import os.log

private let appLog = Logger(subsystem: "com.edu.practice.Voxor", category: "RandIPC")

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        startListeningForNumberRequests()
        startListeningForRecordingRequests()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication,
                     didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    // MARK: - Number request handling

    /// Registers a Darwin notification observer so the keyboard extension can ask
    /// this app to generate a random number at runtime.
    ///
    /// Flow:
    ///  1. Keyboard posts `VoxorIPC.requestName`
    ///  2. This handler generates a number, writes it to the shared App Group
    ///     UserDefaults, then posts `VoxorIPC.readyName`
    ///  3. The keyboard reads the number and inserts it into the active text field
    private func startListeningForRecordingRequests() {
        appLog.debug("startListeningForRecordingRequests: registered observer for '\(VoxorIPC.startRecordingName)'")
        DarwinNotifier.shared.observe(VoxorIPC.startRecordingName) {
            appLog.debug("received startRecording from keyboard extension")
            Task { @MainActor in SimulationManager.shared.start() }
        }
    }

    private func startListeningForNumberRequests() {
        appLog.debug("startListeningForNumberRequests: registered observer for '\(VoxorIPC.requestName)'")
        DarwinNotifier.shared.observe(VoxorIPC.requestName) {
            appLog.debug("received requestNumber from keyboard extension")
            let number = NumberGenerator.generate()
            appLog.debug("generated number: \(number) — writing to sharedDefaults and posting '\(VoxorIPC.readyName)'")
            VoxorIPC.sharedDefaults?.set(number, forKey: VoxorIPC.numberKey)
            VoxorIPC.sharedDefaults?.synchronize()
            DarwinNotifier.shared.post(VoxorIPC.readyName)
            appLog.debug("posted '\(VoxorIPC.readyName)'")
        }
    }
}
