// SimulationManager.swift
// Voxor
//
// Performs live speech-to-text using SFSpeechRecognizer + AVAudioEngine.
// Writes each partial transcription to the shared App Group UserDefaults and
// fires a Darwin notification so the keyboard extension can insert the latest
// text in real time.
//
// On the final result it also sets hasPendingPasteKey = true and posts
// simulationDoneName so the keyboard pastes when it next becomes active.

import Foundation
import UIKit
import Speech
import AVFoundation

@MainActor
final class SimulationManager {

    static let shared = SimulationManager()

    private let speechRecognizer:   SFSpeechRecognizer? = SFSpeechRecognizer(locale: .current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private let audioEngine         = AVAudioEngine()
    private var bgTaskID:           UIBackgroundTaskIdentifier = .invalid
    private var lastText:           String = ""

    // Rolling RMS level updated from the audio tap — read by ViewController.
    private(set) var currentAudioLevel: CGFloat = 0

    private init() {}

    // MARK: - Public API

    /// Starts (or restarts) a live dictation session.
    func start() {
        guard VoxorIPC.sharedDefaults?.bool(forKey: VoxorIPC.isMicEnabledKey) ?? true else { return }
        stop()   // cancel any in-flight session
        reset()

        VoxorIPC.sharedDefaults?.set(true, forKey: VoxorIPC.isRecordingKey)
        VoxorIPC.sharedDefaults?.synchronize()

        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "VoxorRecording") { [weak self] in
            Task { @MainActor [weak self] in self?.endBackgroundTask() }
        }

        SFSpeechRecognizer.requestAuthorization { authStatus in
            guard authStatus == .authorized else { return }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                guard granted else { return }
                Task { @MainActor [weak self] in self?.startRecognition() }
            }
        }
    }

    /// Stops the active dictation session.
    func stop() {
        guard recognitionRequest != nil || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        currentAudioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
        VoxorIPC.sharedDefaults?.set(false, forKey: VoxorIPC.isRecordingKey)
        VoxorIPC.sharedDefaults?.synchronize()
        endBackgroundTask()
    }

    // MARK: - Private

    private func startRecognition() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable,
              !audioEngine.isRunning else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement,
                                                            options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true,
                                                          options: .notifyOthersOnDeactivation)
        } catch { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        let node = audioEngine.inputNode
        let fmt  = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.recognitionRequest?.append(buf)
            // Compute RMS from the PCM buffer for the live waveform visualisation.
            let level = Self.rms(buffer: buf)
            Task { @MainActor [weak self] in self?.currentAudioLevel = level }
        }

        audioEngine.prepare()
        guard (try? audioEngine.start()) != nil else { return }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    if text != self.lastText && !text.isEmpty {
                        self.lastText = text
                        VoxorIPC.sharedDefaults?.set(text, forKey: VoxorIPC.liveTextKey)

                        if result.isFinal {
                            VoxorIPC.sharedDefaults?.set(true,  forKey: VoxorIPC.isFinishedKey)
                            VoxorIPC.sharedDefaults?.set(true,  forKey: VoxorIPC.hasPendingPasteKey)
                            VoxorIPC.sharedDefaults?.set(false, forKey: VoxorIPC.isRecordingKey)
                        }
                        VoxorIPC.sharedDefaults?.synchronize()
                        DarwinNotifier.shared.post(VoxorIPC.simulationUpdateName)

                        if result.isFinal {
                            DarwinNotifier.shared.post(VoxorIPC.simulationDoneName)
                            self.stop()
                        }
                    }
                }

                if error != nil { self.stop() }
            }
        }
    }

    // MARK: - Audio metering

    /// Computes a normalised RMS (0.0 – 1.0) from a PCM buffer.
    private static func rms(buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        let channel = data[0]
        var sum: Float = 0
        for i in 0..<frameCount { sum += channel[i] * channel[i] }
        let rmsRaw = sqrtf(sum / Float(frameCount))
        // Typical speech RMS ~0.01–0.10; scale up so 0.05 → ~0.5
        return CGFloat(min(1.0, rmsRaw * 15.0))
    }

    // MARK: - Helpers

    private func endBackgroundTask() {
        guard bgTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTaskID)
        bgTaskID = .invalid
    }

    private func reset() {
        lastText = ""
        currentAudioLevel = 0
        let d = VoxorIPC.sharedDefaults
        d?.removeObject(forKey: VoxorIPC.liveTextKey)
        d?.set(false, forKey: VoxorIPC.isFinishedKey)
        d?.set(false, forKey: VoxorIPC.isRecordingKey)
        d?.set(false, forKey: VoxorIPC.hasPendingPasteKey)
        d?.synchronize()
    }
}
