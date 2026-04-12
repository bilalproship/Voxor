// NumberGenerator.swift
// Voxor
//
// Compiled into both the Voxor app target and the VoxorKeyboard extension.
// Provides:
//   - VoxorIPC      — shared constants (app group, Darwin notification names, UserDefaults key)
//   - NumberGenerator — cryptographically random integer generation
//   - DarwinNotifier  — cross-process Darwin notification center wrapper

import Foundation
import CoreFoundation

// MARK: - Shared IPC constants

enum VoxorIPC {
    /// App Group shared between the Voxor app and VoxorKeyboard extension.
    /// Must match the value in both .entitlements files.
    static let appGroupID  = "group.com.edu.practice.Voxor"

    /// Posted by the keyboard extension to ask the main app to generate a number.
    static let requestName = "com.edu.practice.Voxor.requestNumber"

    /// Posted by the main app once the number has been written to shared UserDefaults.
    static let readyName   = "com.edu.practice.Voxor.numberReady"

    /// Key under which the generated number is stored in the shared UserDefaults.
    static let numberKey   = "voxor.lastNumber"

    // MARK: - Simulation keys & notification name

    /// Live text chunk written by SimulationManager during a streaming session.
    static let liveTextKey         = "live_text"

    /// Set to `true` by SimulationManager when the last chunk has been sent.
    static let isFinishedKey       = "is_finished"

    /// Set to `true` while a simulation is actively running.
    static let isRecordingKey      = "is_recording"

    /// Darwin notification posted by SimulationManager after each new chunk.
    static let simulationUpdateName = "com.app.simulation.update"

    /// Posted by the keyboard extension to ask the main app to start a recording session.
    static let startRecordingName  = "com.edu.practice.Voxor.startRecording"

    /// Posted by SimulationManager when the last chunk has been written and the
    /// session is fully complete. Both the main app UI and the keyboard extension
    /// observe this to trigger final paste / done-state transitions.
    static let simulationDoneName  = "com.app.simulation.done"

    /// Set to `true` by SimulationManager when the final chunk is committed and
    /// cleared to `false` by the keyboard once it has pasted the result.
    static let hasPendingPasteKey  = "voxor.hasPendingPaste"

    /// `true` while the microphone is globally enabled by the user.
    static let isMicEnabledKey     = "voxor.micEnabled"

    /// Posted whenever the global mic-enabled state changes (enable or disable).
    static let micStateChangedName = "com.edu.practice.Voxor.micStateChanged"

    /// Shared UserDefaults backed by the App Group container.
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}

// MARK: - Random number generation

enum NumberGenerator {
    /// Returns a cryptographically random integer in [min, max].
    static func generate(min: Int = 1, max: Int = 1_000_000) -> Int {
        precondition(min <= max)
        let range = UInt64(bitPattern: Int64(max) - Int64(min)) + 1
        return min + Int(UInt64.random(in: 0..<range))
    }
}

// MARK: - Darwin cross-process notification helper

/// Thread-safe wrapper around CFNotificationCenterGetDarwinNotifyCenter().
/// Darwin notifications cross process boundaries, making them ideal for
/// app ↔ keyboard-extension communication.
///
/// Usage:
///   // In the sender:
///   DarwinNotifier.shared.post(VoxorIPC.requestName)
///
///   // In the receiver:
///   let token = DarwinNotifier.shared.observe(VoxorIPC.readyName) { ... }
///   // Later: DarwinNotifier.shared.remove(name:id:)
final class DarwinNotifier: @unchecked Sendable {

    static let shared = DarwinNotifier()

    // Protected by `lock`. Callbacks are dispatched to the main queue.
    nonisolated(unsafe) private var callbacks: [String: [UUID: () -> Void]] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: Post

    func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }

    // MARK: Observe

    @discardableResult
    func observe(_ name: String, callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        let isFirstRegistration = callbacks[name] == nil
        if isFirstRegistration { callbacks[name] = [:] }
        callbacks[name]?[id] = callback
        lock.unlock()

        if isFirstRegistration {
            // Register a single C-level observer per notification name.
            // The observer pointer is the (never-deallocated) shared singleton.
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                selfPtr,
                { _, observer, cfName, _, _ in
                    guard let observer, let cfName else { return }
                    let notifier = Unmanaged<DarwinNotifier>.fromOpaque(observer)
                                                            .takeUnretainedValue()
                    let nameStr = cfName.rawValue as String
                    notifier.lock.lock()
                    let cbs = notifier.callbacks[nameStr]?.values.map { $0 } ?? []
                    notifier.lock.unlock()
                    // Dispatch to main queue so callers can safely update UI.
                    DispatchQueue.main.async { cbs.forEach { $0() } }
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
        return id
    }

    // MARK: Remove

    func remove(name: String, id: UUID) {
        lock.lock()
        callbacks[name]?.removeValue(forKey: id)
        lock.unlock()
    }
}
