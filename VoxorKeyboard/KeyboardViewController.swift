//
//  KeyboardViewController.swift
//  VoxorKeyboard
//
//  Created by app on 12/4/2026.
//

// Note: "No such module 'UIKit'" is a SourceKit indexing artifact — UIKit is
// always available in keyboard extensions and the project builds normally.

import UIKit
import Speech
import AVFoundation
import os.log

private let kbLog = Logger(subsystem: "com.edu.practice.Voxor.VoxorKeyboard", category: "RandIPC")


class KeyboardViewController: UIInputViewController {

    // MARK: - Types

    enum KBMode  { case letters, numbers, symbols }
    enum Shift   { case off, once, locked }

    // MARK: - State

    private var mode: KBMode = .letters
    private var shift: Shift = .once          // start capitalised (default iOS behaviour)
    private var lastShiftTap: Date = .distantPast

    // MARK: - Speech / dictation

    private let speechRecognizer = SFSpeechRecognizer(locale: .current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var isRecording = false
    private var dictatedLength = 0             // chars inserted by current dictation run

    // MARK: - Simulation listener

    /// Tracks the last text chunk inserted during a simulation to prevent duplicates.
    private var lastInsertedSimText: String = ""
    /// Token for the active Darwin observer so we register it exactly once.
    private var simulationObserverToken: UUID?
    /// Token for the simulationDone observer (paste-on-return path).
    private var simDoneObserverToken: UUID?
    /// Token for the global mic-enabled state observer.
    private var micStateToken: UUID?
    /// True from the moment the user taps mic until the result is pasted.
    private var isMicWaiting = false

    // MARK: - Weak UI references (refreshed on every renderKeys)

    private weak var shiftBtn:  UIButton?
    private weak var micBtn:    UIButton?
    private weak var nextKbdBtn: UIButton?

    // MARK: - Layout constants

    private let toolbarH:  CGFloat = 44
    private let keyH:      CGFloat = 43
    private let hGap:      CGFloat = 6
    private let vGap:      CGFloat = 10
    private let sidePad:   CGFloat = 3
    private let specialW:  CGFloat = 42
    private let bottomW:   CGFloat = 86

    // MARK: - Root containers

    private let keyboardStack = UIStackView()   // vertical, holds 4 rows

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildToolbar()
        buildKeyboard()
        registerSimulationObserver()
        registerSimulationDoneObserver()
        registerMicStateObserver()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // User may have switched back after the simulation finished in the background.
        checkAndPastePendingResult()
        updateMicButtonState()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        nextKbdBtn?.isHidden = !needsInputModeSwitchKey
    }

    // MARK: - Toolbar

    private func buildToolbar() {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        let mic   = tbBtn(icon: "mic.fill",            sel: #selector(micTapped))
        let paste = tbBtn(icon: "doc.on.clipboard",    sel: #selector(pasteTapped))
        let globe = tbBtn(icon: "globe",               sel: #selector(handleInputModeList(from:with:)),
                          allTouchEvents: true)

        micBtn     = mic
        nextKbdBtn = globe

        [mic, paste, globe].forEach { bar.addSubview($0) }

        let sep = UIView()
        sep.backgroundColor = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(sep)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: toolbarH),

            mic.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            mic.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            mic.widthAnchor.constraint(equalToConstant: 36),
            mic.heightAnchor.constraint(equalToConstant: 36),

            paste.leadingAnchor.constraint(equalTo: mic.trailingAnchor, constant: 6),
            paste.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            paste.widthAnchor.constraint(equalToConstant: 36),
            paste.heightAnchor.constraint(equalToConstant: 36),
 
            globe.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            globe.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            globe.widthAnchor.constraint(equalToConstant: 36),
            globe.heightAnchor.constraint(equalToConstant: 36),

            sep.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    private func tbBtn(icon: String, sel: Selector, allTouchEvents: Bool = false) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: icon), for: .normal)
        b.tintColor = .label
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: sel, for: allTouchEvents ? .allTouchEvents : .touchUpInside)
        return b
    }

    private func tbBtn(title: String, sel: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        b.tintColor = .label
        b.backgroundColor = .systemBlue.withAlphaComponent(0.15)
        b.layer.cornerRadius = 6
        b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: sel, for: .touchUpInside)
        return b
    }

    // MARK: - Keyboard container

    private func buildKeyboard() {
        keyboardStack.axis    = .vertical
        keyboardStack.spacing = vGap
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardStack)

        NSLayoutConstraint.activate([
            keyboardStack.topAnchor.constraint(equalTo: view.topAnchor, constant: toolbarH + 8),
            keyboardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: sidePad),
            keyboardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -sidePad),
            keyboardStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
        ])

        renderKeys()
    }

    // MARK: - Key rendering (called on mode/shift/appearance changes)

    private func renderKeys() {
        keyboardStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch mode {
        case .letters:
            keyboardStack.addArrangedSubview(makeEqualRow(["Q","W","E","R","T","Y","U","I","O","P"]))
            keyboardStack.addArrangedSubview(makeCenteredRow(["A","S","D","F","G","H","J","K","L"]))
            keyboardStack.addArrangedSubview(makeShiftRow())
            keyboardStack.addArrangedSubview(makeBottomRow(left: "123", leftSel: #selector(numTapped),
                                                           right: "return", rightSel: #selector(returnTapped)))

        case .numbers:
            keyboardStack.addArrangedSubview(makeEqualRow(["1","2","3","4","5","6","7","8","9","0"]))
            keyboardStack.addArrangedSubview(makeEqualRow(["-","/",":",";","(",")","$","&","@","\""]))
            keyboardStack.addArrangedSubview(makeMidSpecialRow(chars: [".",",","?","!","'"],
                                                               leftTitle: "#+=", leftSel: #selector(symTapped)))
            keyboardStack.addArrangedSubview(makeBottomRow(left: "ABC", leftSel: #selector(abcTapped),
                                                           right: "return", rightSel: #selector(returnTapped)))

        case .symbols:
            keyboardStack.addArrangedSubview(makeEqualRow(["[","]","{","}","#","%","^","*","+","="]))
            keyboardStack.addArrangedSubview(makeEqualRow(["_","\\","|","~","<",">","€","£","¥","•"]))
            keyboardStack.addArrangedSubview(makeMidSpecialRow(chars: [".",",","?","!","'"],
                                                               leftTitle: "123", leftSel: #selector(numTapped)))
            keyboardStack.addArrangedSubview(makeBottomRow(left: "ABC", leftSel: #selector(abcTapped),
                                                           right: "return", rightSel: #selector(returnTapped)))
        }
    }

    // MARK: - Row builders

    /// Full-width row, all keys equal width
    private func makeEqualRow(_ keys: [String]) -> UIStackView {
        let s = hStack(equal: true)
        keys.forEach { s.addArrangedSubview(charKey($0)) }
        return s
    }

    /// 9-key row (A–L) rendered at ~90% width and centred
    private func makeCenteredRow(_ keys: [String]) -> UIView {
        let wrapper = UIView()
        let inner   = hStack(equal: true)
        keys.forEach { inner.addArrangedSubview(charKey($0)) }
        inner.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: wrapper.topAnchor),
            inner.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            inner.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            inner.widthAnchor.constraint(equalTo: wrapper.widthAnchor, multiplier: 0.9),
        ])
        return wrapper
    }

    /// ⇧  Z X C V B N M  ⌫
    private func makeShiftRow() -> UIStackView {
        let s = hStack(equal: false)

        let shBt = specialKey(shiftTitle())
        shBt.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
        shiftBtn = shBt
        applyShiftStyle(shBt)
        s.addArrangedSubview(shBt)

        let letters = hStack(equal: true)
        ["Z","X","C","V","B","N","M"].forEach { letters.addArrangedSubview(charKey($0)) }
        s.addArrangedSubview(letters)

        let del = specialKey("⌫")
        del.addTarget(self, action: #selector(delTapped), for: .touchUpInside)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(delHeld(_:)))
        lp.minimumPressDuration = 0.35
        del.addGestureRecognizer(lp)
        s.addArrangedSubview(del)

        shBt.widthAnchor.constraint(equalToConstant: specialW).isActive = true
        del.widthAnchor.constraint(equalToConstant: specialW).isActive  = true
        return s
    }

    /// [leftSpecial]  .  ,  ?  !  '  [⌫]  — used in number/symbol pages
    private func makeMidSpecialRow(chars: [String], leftTitle: String, leftSel: Selector) -> UIStackView {
        let s = hStack(equal: false)

        let left = specialKey(leftTitle, smallFont: true)
        left.addTarget(self, action: leftSel, for: .touchUpInside)
        s.addArrangedSubview(left)

        let mid = hStack(equal: true)
        chars.forEach { mid.addArrangedSubview(charKey($0)) }
        s.addArrangedSubview(mid)

        let del = specialKey("⌫")
        del.addTarget(self, action: #selector(delTapped), for: .touchUpInside)
        s.addArrangedSubview(del)

        left.widthAnchor.constraint(equalToConstant: specialW).isActive = true
        del.widthAnchor.constraint(equalToConstant: specialW).isActive  = true
        return s
    }

    /// [leftLabel]  [   s p a c e   ]  [rightLabel]
    private func makeBottomRow(left: String, leftSel: Selector,
                               right: String, rightSel: Selector) -> UIStackView {
        let s = hStack(equal: false)

        let leftKey = specialKey(left, smallFont: true)
        leftKey.addTarget(self, action: leftSel, for: .touchUpInside)

        let spaceKey = UIButton(type: .custom)
        spaceKey.setTitle("space", for: .normal)
        spaceKey.titleLabel?.font = .systemFont(ofSize: 15)
        spaceKey.setTitleColor(keyFg, for: .normal)
        spaceKey.backgroundColor = keyBg
        applyKeyStyle(spaceKey)
        spaceKey.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)

        let rightKey = specialKey(right, smallFont: true)
        rightKey.addTarget(self, action: rightSel, for: .touchUpInside)

        s.addArrangedSubview(leftKey)
        s.addArrangedSubview(spaceKey)
        s.addArrangedSubview(rightKey)

        leftKey.widthAnchor.constraint(equalToConstant: bottomW).isActive  = true
        rightKey.widthAnchor.constraint(equalToConstant: bottomW).isActive = true
        return s
    }

    // MARK: - Key factories

    private func charKey(_ char: String) -> UIButton {
        let b = UIButton(type: .custom)
        let label: String
        if mode == .letters {
            label = shift != .off ? char.uppercased() : char.lowercased()
        } else {
            label = char
        }
        b.setTitle(label, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .light)
        b.setTitleColor(keyFg, for: .normal)
        b.backgroundColor = keyBg
        applyKeyStyle(b)
        b.accessibilityIdentifier = char        // raw value used in charTapped
        b.addTarget(self, action: #selector(charTapped(_:)), for: .touchUpInside)
        return b
    }

    private func specialKey(_ title: String, smallFont: Bool = false) -> UIButton {
        let b = UIButton(type: .custom)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = smallFont
            ? .systemFont(ofSize: 15, weight: .regular)
            : .systemFont(ofSize: 17, weight: .light)
        b.setTitleColor(keyFg, for: .normal)
        b.backgroundColor = specialBg
        applyKeyStyle(b)
        return b
    }

    private func applyKeyStyle(_ b: UIButton) {
        b.layer.cornerRadius  = 5
        b.layer.shadowColor   = UIColor.black.cgColor
        b.layer.shadowOffset  = CGSize(width: 0, height: 1)
        b.layer.shadowRadius  = 0
        b.layer.shadowOpacity = 0.35
        b.layer.masksToBounds = false
        b.heightAnchor.constraint(equalToConstant: keyH).isActive = true
    }

    private func hStack(equal: Bool) -> UIStackView {
        let s = UIStackView()
        s.axis         = .horizontal
        s.spacing      = hGap
        s.distribution = equal ? .fillEqually : .fill
        return s
    }

    // MARK: - Adaptive colors

    private var isDark: Bool { textDocumentProxy.keyboardAppearance == .dark }

    private var keyBg:     UIColor { isDark ? UIColor(white: 0.35, alpha: 1) : .white }
    private var specialBg: UIColor { isDark ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.67, alpha: 1) }
    private var keyFg:     UIColor { isDark ? .white : .black }
    private var bgColor:   UIColor { isDark ? UIColor(white: 0.16, alpha: 1) : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1) }
    private var toolbarBg: UIColor { isDark ? UIColor(white: 0.21, alpha: 1) : UIColor(white: 0.82, alpha: 1) }

    // MARK: - Shift helpers

    private func shiftTitle() -> String { shift == .locked ? "⇪" : "⇧" }

    private func applyShiftStyle(_ btn: UIButton) {
        switch shift {
        case .off:
            btn.backgroundColor = specialBg
            btn.setTitleColor(keyFg, for: .normal)
        case .once:
            btn.backgroundColor = keyBg
            btn.setTitleColor(.systemBlue, for: .normal)
        case .locked:
            btn.backgroundColor = .systemBlue
            btn.setTitleColor(.white, for: .normal)
        }
    }

    // MARK: - Key actions

    @objc private func charTapped(_ sender: UIButton) {
        guard let raw = sender.accessibilityIdentifier else { return }
        let out = mode == .letters
            ? (shift != .off ? raw.uppercased() : raw.lowercased())
            : raw
        textDocumentProxy.insertText(out)
        if shift == .once {
            shift = .off
            renderKeys()
        }
    }

    @objc private func spaceTapped()  { textDocumentProxy.insertText(" ") }
    @objc private func returnTapped() { textDocumentProxy.insertText("\n") }

    @objc private func delTapped() { textDocumentProxy.deleteBackward() }

    private var repeatTimer: Timer?

    @objc private func delHeld(_ gr: UILongPressGestureRecognizer) {
        switch gr.state {
        case .began:
            repeatTimer = .scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                self?.textDocumentProxy.deleteBackward()
            }
        case .ended, .cancelled, .failed:
            repeatTimer?.invalidate()
            repeatTimer = nil
        default: break
        }
    }

    @objc private func shiftTapped() {
        let now = Date()
        let isDouble = now.timeIntervalSince(lastShiftTap) < 0.35
        lastShiftTap = now
        switch shift {
        case .off:    shift = isDouble ? .locked : .once
        case .once:   shift = isDouble ? .locked : .off
        case .locked: shift = .off
        }
        renderKeys()
        if let btn = shiftBtn { applyShiftStyle(btn) }
    }

    @objc private func numTapped() { mode = .numbers; renderKeys() }
    @objc private func symTapped() { mode = .symbols; renderKeys() }
    @objc private func abcTapped() { mode = .letters; renderKeys() }

    @objc private func pasteTapped() {
        guard let text = UIPasteboard.general.string else { return }
        textDocumentProxy.insertText(text)
    }

    // MARK: - Random number via main-app IPC

    /// Token that identifies the active "numberReady" Darwin observer, so we can
    /// remove it once we receive the response.
    private var randObserverToken: UUID?

    /// Requests a random number from the Voxor main app via Darwin notification +
    /// shared App Group UserDefaults, then inserts the result into the active field.
    ///
    /// Flow:
    ///  1. Register one-time "numberReady" observer
    ///  2. Post "requestNumber" → main app receives it, generates number, writes
    ///     to shared UserDefaults, posts "numberReady"
    ///  3. Keyboard reads the value and inserts it
    ///  If the main app is not running, nothing is inserted.
    @objc private func randTapped() {
        // Prevent duplicate in-flight requests
        guard randObserverToken == nil else {
            kbLog.debug("randTapped: request already in-flight, ignoring")
            return
        }

        kbLog.debug("randTapped: registering observer and posting requestNumber")

        // Step 1 — listen for the main app's response
        randObserverToken = DarwinNotifier.shared.observe(VoxorIPC.readyName) { [weak self] in
            self?.handleNumberReady()
        }

        // Step 2 — request generation from the main app
        DarwinNotifier.shared.post(VoxorIPC.requestName)
        kbLog.debug("randTapped: posted '\(VoxorIPC.requestName)' — waiting for main app response")
    }

    private func handleNumberReady() {
        kbLog.debug("handleNumberReady: received '\(VoxorIPC.readyName)' from main app")
        cancelRandObserver()
        guard let number = VoxorIPC.sharedDefaults?.integer(forKey: VoxorIPC.numberKey) else {
            kbLog.error("handleNumberReady: sharedDefaults has no value for key '\(VoxorIPC.numberKey)' — nothing inserted")
            return
        }
        kbLog.debug("handleNumberReady: inserting number \(number)")
        textDocumentProxy.insertText(String(number))
    }

    private func cancelRandObserver() {
        if let token = randObserverToken {
            kbLog.debug("cancelRandObserver: removing observer token \(token)")
            DarwinNotifier.shared.remove(name: VoxorIPC.readyName, id: token)
            randObserverToken = nil
        }
    }

    // MARK: - Simulation observer

    /// Registers exactly once for `com.app.simulation.update` Darwin notifications.
    private func registerSimulationObserver() {
        guard simulationObserverToken == nil else { return }
        simulationObserverToken = DarwinNotifier.shared.observe(VoxorIPC.simulationUpdateName) { [weak self] in
            self?.handleSimulationUpdate()
        }
        kbLog.debug("registerSimulationObserver: observer registered")
    }

    /// Registers for the done notification (fires once per session after the last chunk).
    /// Used as the primary paste trigger when the keyboard was backgrounded during streaming.
    private func registerSimulationDoneObserver() {
        guard simDoneObserverToken == nil else { return }
        simDoneObserverToken = DarwinNotifier.shared.observe(VoxorIPC.simulationDoneName) { [weak self] in
            self?.handleSimulationDone()
        }
        kbLog.debug("registerSimulationDoneObserver: observer registered")
    }

    /// Observes the global mic-enabled state so the button icon/colour stays in sync
    /// with whatever the user toggles in the main app.
    private func registerMicStateObserver() {
        guard micStateToken == nil else { return }
        micStateToken = DarwinNotifier.shared.observe(VoxorIPC.micStateChangedName) { [weak self] in
            self?.updateMicButtonState()
        }
        kbLog.debug("registerMicStateObserver: observer registered")
    }

    /// Shows a brief banner informing the user the mic is disabled in the main app.
    private func showMicDisabledBanner() {
        let banner = UILabel()
        banner.text = "Microphone is disabled — open Voxor to enable it"
        banner.font = .systemFont(ofSize: 11, weight: .medium)
        banner.textColor = .white
        banner.backgroundColor = UIColor.systemGray.withAlphaComponent(0.92)
        banner.textAlignment = .center
        banner.numberOfLines = 2
        banner.layer.cornerRadius = 8
        banner.layer.masksToBounds = true
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            banner.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            banner.heightAnchor.constraint(equalToConstant: 36),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            banner.removeFromSuperview()
        }
    }

    /// Reads the latest live_text chunk from the shared App Group and inserts it
    /// into the active text field, replacing any previously inserted chunk.
    /// Duplicate chunks (same text as last time) are skipped.
    private func handleSimulationUpdate() {
        guard let text = VoxorIPC.sharedDefaults?.string(forKey: VoxorIPC.liveTextKey),
              !text.isEmpty,
              text != lastInsertedSimText else {
            kbLog.debug("handleSimulationUpdate: no new text or duplicate — skipping")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Delete the previous chunk before inserting the new one
            let deleteCount = self.lastInsertedSimText.count
            for _ in 0..<deleteCount { self.textDocumentProxy.deleteBackward() }
            self.textDocumentProxy.insertText(text)
            self.lastInsertedSimText = text
            kbLog.debug("handleSimulationUpdate: inserted '\(text)'")

            // If SimulationManager already marked the session finished (isFinishedKey
            // is set before the final simulationUpdateName is posted), consume the
            // pending paste flag here — the text is already in the field.
            let isFinished = VoxorIPC.sharedDefaults?.bool(forKey: VoxorIPC.isFinishedKey) ?? false
            if isFinished {
                VoxorIPC.sharedDefaults?.set(false, forKey: VoxorIPC.hasPendingPasteKey)
                VoxorIPC.sharedDefaults?.synchronize()
                self.lastInsertedSimText = ""
                self.isMicWaiting = false
                self.updateMicButtonState()
                kbLog.debug("handleSimulationUpdate: session finished via streaming — paste consumed")
            }
        }
    }

    /// Called when the main app posts simulationDoneName (arrives after the last
    /// simulationUpdateName on the main queue). If the keyboard was backgrounded and
    /// missed the streaming updates, this is where the result gets pasted.
    private func handleSimulationDone() {
        kbLog.debug("handleSimulationDone: received simulationDone — isMicWaiting=\(self.isMicWaiting)")
        checkAndPastePendingResult()
    }

    // MARK: - Paste-on-return

    /// Pastes the final transcription result if one is waiting and the keyboard
    /// hasn't already consumed it via live streaming.
    /// Safe to call any time — guards on both isMicWaiting and hasPendingPasteKey.
    private func checkAndPastePendingResult() {
        guard isMicWaiting else { return }
        guard let defaults  = VoxorIPC.sharedDefaults,
              defaults.bool(forKey: VoxorIPC.hasPendingPasteKey),
              let finalText = defaults.string(forKey: VoxorIPC.liveTextKey),
              !finalText.isEmpty else {
            kbLog.debug("checkAndPastePendingResult: nothing to paste (hasPendingPaste=\(VoxorIPC.sharedDefaults?.bool(forKey: VoxorIPC.hasPendingPasteKey) ?? false))")
            return
        }
        // Remove any partial text already streamed into the field, then insert final.
        let prevCount = lastInsertedSimText.count
        for _ in 0..<prevCount { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(finalText)
        kbLog.debug("checkAndPastePendingResult: pasted '\(finalText)' (deleted \(prevCount) chars)")
        // Mark consumed
        defaults.set(false, forKey: VoxorIPC.hasPendingPasteKey)
        defaults.synchronize()
        lastInsertedSimText = ""
        isMicWaiting = false
        updateMicButtonState()
    }

    // MARK: - Mic button state

    private func updateMicButtonState() {
        let isGloballyEnabled = VoxorIPC.sharedDefaults?.bool(forKey: VoxorIPC.isMicEnabledKey) ?? true

        if !isGloballyEnabled {
            micBtn?.layer.removeAnimation(forKey: "micPulse")
            micBtn?.setImage(UIImage(systemName: "mic.slash"), for: .normal)
            micBtn?.tintColor = .systemRed
            // Cancel any in-flight wait since the mic is now off
            if isMicWaiting {
                isMicWaiting = false
                lastInsertedSimText = ""
            }
        } else if isRecording {
            micBtn?.layer.removeAnimation(forKey: "micPulse")
            micBtn?.setImage(UIImage(systemName: "mic.fill"), for: .normal)
            micBtn?.tintColor = .systemGreen
        } else if isMicWaiting {
            micBtn?.setImage(UIImage(systemName: "mic.fill"), for: .normal)
            micBtn?.tintColor = .systemOrange
            if micBtn?.layer.animation(forKey: "micPulse") == nil {
                let anim          = CABasicAnimation(keyPath: "opacity")
                anim.fromValue    = 1.0
                anim.toValue      = 0.35
                anim.duration     = 0.65
                anim.autoreverses = true
                anim.repeatCount  = .infinity
                micBtn?.layer.add(anim, forKey: "micPulse")
            }
        } else {
            micBtn?.layer.removeAnimation(forKey: "micPulse")
            micBtn?.setImage(UIImage(systemName: "mic.fill"), for: .normal)
            micBtn?.tintColor = .systemRed
        }
    }

    // MARK: - Microphone / Speech-to-text

    /// Tapping the mic button opens the main Voxor app via URL scheme (which works
    /// whether the app is running or not), then also posts the Darwin notification
    /// as a fast path for when the app is already alive in the background.
    @objc private func micTapped() {
        guard hasFullAccess else {
            showFullAccessBanner()
            return
        }
//        guard VoxorIPC.sharedDefaults?.bool(forKey: VoxorIPC.isMicEnabledKey) ?? true else {
//            showMicDisabledBanner()
//            return
//        }
        // Clear any unconsumed result from a previous session before starting fresh.
        VoxorIPC.sharedDefaults?.set(false, forKey: VoxorIPC.hasPendingPasteKey)
        VoxorIPC.sharedDefaults?.removeObject(forKey: VoxorIPC.liveTextKey)
        VoxorIPC.sharedDefaults?.synchronize()
        lastInsertedSimText = ""
        isMicWaiting = true
        updateMicButtonState()
        openMainApp(url: URL(string: "voxor://startRecording")!)
        DarwinNotifier.shared.post(VoxorIPC.startRecordingName)
        kbLog.debug("micTapped: isMicWaiting=true, opened app + posted startRecording")
    }

    private func openMainApp(url: URL) {
        guard let app = UIApplication.value(forKeyPath: "sharedApplication") as? UIApplication else {
            kbLog.error("openMainApp: cannot reach UIApplication")
            return
        }
        app.open(url, options: [:]) { success in
            kbLog.debug("openMainApp: open completed, success=\(success)")
        }
    }

    /// Shows a temporary banner telling the user to enable full access in Settings.
    private func showFullAccessBanner() {
        let banner = UILabel()
        banner.text = "Enable Full Access in Settings → General → Keyboards → VoxorKeyboard"
        banner.font = .systemFont(ofSize: 11, weight: .medium)
        banner.textColor = .white
        banner.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.92)
        banner.textAlignment = .center
        banner.numberOfLines = 2
        banner.layer.cornerRadius = 8
        banner.layer.masksToBounds = true
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            banner.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            banner.heightAnchor.constraint(equalToConstant: 36),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            banner.removeFromSuperview()
        }
        kbLog.debug("showFullAccessBanner: hasFullAccess=false")
    }


    // MARK: - UIInputViewController callbacks

    override func textWillChange(_ textInput: UITextInput?) {
        // Prepare for upcoming text change if needed
    }

    override func textDidChange(_ textInput: UITextInput?) {
        // Re-tint toolbar and background to match host app's keyboard appearance
        view.backgroundColor = bgColor

        if let bar = view.subviews.first(where: { !($0 is UIStackView) }) {
            bar.backgroundColor = toolbarBg
        }

        // Apply mic waiting state first, then fall back to appearance-based tint.
        updateMicButtonState()
        nextKbdBtn?.tintColor = isDark ? .white : .label

        renderKeys()
        // Safety-net: paste any result that arrived while the keyboard was away.
        checkAndPastePendingResult()
    }
}
