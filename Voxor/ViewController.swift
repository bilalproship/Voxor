//
//  ViewController.swift
//  Voxor
//
//  Recording screen shown when the keyboard extension opens the app via the
//  voxor://startRecording URL scheme.  Observes Darwin notifications from
//  SimulationManager to display live transcription text, drives the waveform
//  bars from real audio metering, and transitions to a completion state that
//  tells the user to switch back to the keyboard.
//

import UIKit
import os.log

private let vcLog = Logger(subsystem: "com.edu.practice.Voxor", category: "RecordingUI")

class ViewController: UIViewController {

    // Keep IBOutlet so the storyboard connection stays valid; hidden at runtime.
    @IBOutlet weak var textField: UITextField!

    // MARK: - UI

    private let pulseDot           = UIView()
    private let waveformStack      = UIStackView()
    private let transcriptionCard  = UIView()
    private let transcriptionLabel = UILabel()
    private let placeholderLabel   = UILabel()
    private let statusLabel        = UILabel()
    private let hintLabel          = UILabel()

    // MARK: - State

    private var waveBarViews: [UIView] = []
    private var displayLink: CADisplayLink?
    private var isDone = false

    // MARK: - IPC tokens

    private var simUpdateToken: UUID?
    private var simDoneToken:   UUID?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        textField?.isHidden = true
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isDone = false
        pulseDot.backgroundColor = .systemRed
        pulseDot.transform = .identity
        registerObservers()
        syncFromSharedState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeObservers()
        stopWaveform()
    }

    // MARK: - UI Construction

    private func buildUI() {
        view.backgroundColor = .systemBackground

        // ── Header ──────────────────────────────────────────────────
        let iconView = UIImageView(image: UIImage(systemName: "waveform.circle.fill"))
        iconView.tintColor = .systemRed
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Voxor"
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Voice to Text"
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // ── Pulse dot ────────────────────────────────────────────────
        pulseDot.backgroundColor = .systemRed
        pulseDot.layer.cornerRadius = 40
        pulseDot.translatesAutoresizingMaskIntoConstraints = false

        let micIcon = UIImageView(image: UIImage(systemName: "mic.fill"))
        micIcon.tintColor = .white
        micIcon.contentMode = .scaleAspectFit
        micIcon.translatesAutoresizingMaskIntoConstraints = false
        pulseDot.addSubview(micIcon)

        // ── Waveform bars ────────────────────────────────────────────
        waveformStack.axis         = .horizontal
        waveformStack.spacing      = 5
        waveformStack.alignment    = .center
        waveformStack.distribution = .fillEqually
        waveformStack.translatesAutoresizingMaskIntoConstraints = false

        for _ in 0..<11 {
            let bar = UIView()
            bar.backgroundColor = .systemRed
            bar.layer.cornerRadius = 3
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.widthAnchor.constraint(equalToConstant: 5).isActive  = true
            bar.heightAnchor.constraint(equalToConstant: 40).isActive = true
            bar.transform = CGAffineTransform(scaleX: 1, y: 0.1)
            waveformStack.addArrangedSubview(bar)
            waveBarViews.append(bar)
        }

        // ── Transcription card ───────────────────────────────────────
        transcriptionCard.backgroundColor  = .secondarySystemBackground
        transcriptionCard.layer.cornerRadius = 16
        transcriptionCard.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.text          = "Listening…"
        placeholderLabel.font          = .systemFont(ofSize: 16)
        placeholderLabel.textColor     = .tertiaryLabel
        placeholderLabel.textAlignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        transcriptionLabel.text          = ""
        transcriptionLabel.font          = .systemFont(ofSize: 18, weight: .regular)
        transcriptionLabel.textColor     = .label
        transcriptionLabel.numberOfLines = 0
        transcriptionLabel.textAlignment = .center
        transcriptionLabel.isHidden      = true
        transcriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        transcriptionCard.addSubview(placeholderLabel)
        transcriptionCard.addSubview(transcriptionLabel)

        // ── Status / hint ────────────────────────────────────────────
        statusLabel.text          = "Recording"
        statusLabel.font          = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor     = .systemRed
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.text          = "Switch back to your keyboard when done"
        hintLabel.font          = .systemFont(ofSize: 13)
        hintLabel.textColor     = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        // ── Add to view ──────────────────────────────────────────────
        [iconView, titleLabel, subtitleLabel,
         pulseDot, waveformStack,
         transcriptionCard, statusLabel, hintLabel].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 48),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            pulseDot.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 48),
            pulseDot.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pulseDot.widthAnchor.constraint(equalToConstant: 80),
            pulseDot.heightAnchor.constraint(equalToConstant: 80),

            micIcon.centerXAnchor.constraint(equalTo: pulseDot.centerXAnchor),
            micIcon.centerYAnchor.constraint(equalTo: pulseDot.centerYAnchor),
            micIcon.widthAnchor.constraint(equalToConstant: 36),
            micIcon.heightAnchor.constraint(equalToConstant: 36),

            waveformStack.topAnchor.constraint(equalTo: pulseDot.bottomAnchor, constant: 24),
            waveformStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            waveformStack.widthAnchor.constraint(equalToConstant: 120),
            waveformStack.heightAnchor.constraint(equalToConstant: 44),

            transcriptionCard.topAnchor.constraint(equalTo: waveformStack.bottomAnchor, constant: 28),
            transcriptionCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            transcriptionCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            transcriptionCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),

            placeholderLabel.centerXAnchor.constraint(equalTo: transcriptionCard.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: transcriptionCard.centerYAnchor),

            transcriptionLabel.topAnchor.constraint(equalTo: transcriptionCard.topAnchor, constant: 20),
            transcriptionLabel.leadingAnchor.constraint(equalTo: transcriptionCard.leadingAnchor, constant: 20),
            transcriptionLabel.trailingAnchor.constraint(equalTo: transcriptionCard.trailingAnchor, constant: -20),
            transcriptionLabel.bottomAnchor.constraint(equalTo: transcriptionCard.bottomAnchor, constant: -20),

            statusLabel.topAnchor.constraint(equalTo: transcriptionCard.bottomAnchor, constant: 20),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            hintLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: - Darwin observers

    private func registerObservers() {
        guard simUpdateToken == nil else { return }
        simUpdateToken = DarwinNotifier.shared.observe(VoxorIPC.simulationUpdateName) { [weak self] in
            self?.onUpdate()
        }
        simDoneToken = DarwinNotifier.shared.observe(VoxorIPC.simulationDoneName) { [weak self] in
            self?.onDone()
        }
        vcLog.debug("registerObservers: registered for update + done")
    }

    private func removeObservers() {
        if let t = simUpdateToken {
            DarwinNotifier.shared.remove(name: VoxorIPC.simulationUpdateName, id: t)
            simUpdateToken = nil
        }
        if let t = simDoneToken {
            DarwinNotifier.shared.remove(name: VoxorIPC.simulationDoneName, id: t)
            simDoneToken = nil
        }
    }

    // MARK: - Recognition callbacks

    private func onUpdate() {
        guard let text = VoxorIPC.sharedDefaults?.string(forKey: VoxorIPC.liveTextKey),
              !text.isEmpty else { return }
        if displayLink == nil { startWaveform() }
        showText(text)
        vcLog.debug("onUpdate: '\(text)'")
    }

    private func onDone() {
        guard !isDone else { return }
        isDone = true
        if let text = VoxorIPC.sharedDefaults?.string(forKey: VoxorIPC.liveTextKey),
           !text.isEmpty { showText(text) }
        showDoneState()
        vcLog.debug("onDone: recording finished")
    }

    // MARK: - UI helpers

    private func showText(_ text: String) {
        UIView.transition(with: transcriptionCard, duration: 0.2, options: .transitionCrossDissolve) {
            self.placeholderLabel.isHidden   = true
            self.transcriptionLabel.isHidden = false
            self.transcriptionLabel.text     = text
        }
    }

    private func showDoneState() {
        stopWaveform()
        UIView.animate(withDuration: 0.4, delay: 0,
                       usingSpringWithDamping: 0.65, initialSpringVelocity: 0.5,
                       options: [], animations: {
            self.pulseDot.backgroundColor = .systemGreen
            self.pulseDot.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        })
        UIView.transition(with: statusLabel, duration: 0.3, options: .transitionCrossDissolve) {
            self.statusLabel.text      = "Complete ✓"
            self.statusLabel.textColor = .systemGreen
        }
        UIView.transition(with: hintLabel, duration: 0.3, options: .transitionCrossDissolve) {
            self.hintLabel.text = "Switch back to your keyboard — text will be pasted automatically"
        }
    }

    /// Populates UI from shared state in case the VC appears after recognition
    /// has already started (e.g. app was relaunched mid-session).
    private func syncFromSharedState() {
        let isRecording = VoxorIPC.sharedDefaults?.bool(forKey: VoxorIPC.isRecordingKey) ?? false
        let isFinished  = VoxorIPC.sharedDefaults?.bool(forKey: VoxorIPC.isFinishedKey)  ?? false
        let text        = VoxorIPC.sharedDefaults?.string(forKey: VoxorIPC.liveTextKey)  ?? ""

        if !text.isEmpty { showText(text) }

        if isFinished {
            onDone()
        } else if isRecording {
            startWaveform()
        }
    }

    // MARK: - Waveform (audio-level driven via CADisplayLink)

    private func startWaveform() {
        guard displayLink == nil else { return }
        startPulse()
        displayLink = CADisplayLink(target: self, selector: #selector(updateWaveform))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateWaveform() {
        // Sample the current microphone level from SimulationManager.
        let level = SimulationManager.shared.currentAudioLevel   // 0.0 – 1.0
        let count = waveBarViews.count

        for (i, bar) in waveBarViews.enumerated() {
            // Spread a sine-shaped envelope across bars, modulated by the mic level.
            let phase  = Double(i) / Double(count - 1) * .pi          // 0 … π
            let shape  = CGFloat(sin(phase))                           // 0→1→0 envelope
            let noise  = CGFloat.random(in: 0.85...1.15)               // ±15% jitter
            let scale  = max(0.08, level * shape * noise)
            UIView.animate(withDuration: 0.08, delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState]) {
                bar.transform = CGAffineTransform(scaleX: 1, y: scale)
            }
        }
    }

    private func startPulse() {
        let anim            = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue      = 1.0
        anim.toValue        = 1.1
        anim.duration       = 0.7
        anim.autoreverses   = true
        anim.repeatCount    = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulseDot.layer.add(anim, forKey: "pulse")
    }

    private func stopWaveform() {
        displayLink?.invalidate()
        displayLink = nil
        pulseDot.layer.removeAnimation(forKey: "pulse")
        UIView.animate(withDuration: 0.25) {
            for bar in self.waveBarViews {
                bar.transform = CGAffineTransform(scaleX: 1, y: 0.1)
            }
        }
    }
}
