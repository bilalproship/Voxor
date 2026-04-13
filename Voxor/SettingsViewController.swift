//
//  SettingsViewController.swift
//  Voxor
//
//  Root screen of the main app. Shows whether the VoxorKeyboard extension is
//  enabled and has Full Access. When either check fails the user can tap a
//  button to jump straight to the iOS Keyboard settings page.
//

import UIKit

final class SettingsViewController: UIViewController {

    // MARK: - UI

    private let iconView        = UIImageView()
    private let titleLabel      = UILabel()
    private let subtitleLabel   = UILabel()
    private let cardView        = UIView()
    private let enabledRow      = StatusRowView()
    private let fullAccessRow   = StatusRowView()
    private let divider         = UIView()
    private let openSettingsBtn = UIButton(type: .system)
    private let hintLabel       = UILabel()
    private let allSetLabel     = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        refreshStatus()
    }

    // MARK: - Status

    private func refreshStatus() {
        let defaults    = VoxorIPC.sharedDefaults
        let isEnabled   = defaults?.bool(forKey: VoxorIPC.keyboardEnabledKey)    ?? false
        let hasAccess   = defaults?.bool(forKey: VoxorIPC.keyboardFullAccessKey) ?? false

        enabledRow.configure(
            icon: "keyboard",
            title: "Keyboard Enabled",
            isGranted: isEnabled
        )
        fullAccessRow.configure(
            icon: "lock.shield",
            title: "Full Access",
            isGranted: hasAccess
        )

        let allGood = isEnabled && hasAccess
        openSettingsBtn.isHidden = allGood
        hintLabel.isHidden       = allGood
        allSetLabel.isHidden     = !allGood
    }

    // MARK: - Actions

    @objc private func openSettingsTapped() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - UI Construction

    private func buildUI() {
        view.backgroundColor = .systemGroupedBackground

        // ── Icon + branding ──────────────────────────────────────────
        iconView.image = UIImage(systemName: "waveform.circle.fill")
        iconView.tintColor = .systemRed
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Voxor"
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = "Voice to Text Keyboard"
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // ── Status card ──────────────────────────────────────────────
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = 12
        cardView.translatesAutoresizingMaskIntoConstraints = false

        enabledRow.translatesAutoresizingMaskIntoConstraints = false
        fullAccessRow.translatesAutoresizingMaskIntoConstraints = false

        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        [enabledRow, divider, fullAccessRow].forEach { cardView.addSubview($0) }

        // ── "All set" label (shown when both permissions granted) ────
        allSetLabel.text = "Keyboard is ready to use"
        allSetLabel.font = .systemFont(ofSize: 15, weight: .medium)
        allSetLabel.textColor = .systemGreen
        allSetLabel.textAlignment = .center
        allSetLabel.isHidden = true
        allSetLabel.translatesAutoresizingMaskIntoConstraints = false

        // ── Open Settings button ─────────────────────────────────────
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Open Keyboard Settings"
        cfg.baseBackgroundColor = .systemRed
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .large
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs; a.font = UIFont.systemFont(ofSize: 17, weight: .semibold); return a
        }
        openSettingsBtn.configuration = cfg
        openSettingsBtn.translatesAutoresizingMaskIntoConstraints = false
        openSettingsBtn.addTarget(self, action: #selector(openSettingsTapped), for: .touchUpInside)

        // ── Hint ─────────────────────────────────────────────────────
        hintLabel.text = "Settings → General → Keyboard → Keyboards → VoxorKeyboard\nThen enable Full Access"
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        // ── Assemble ─────────────────────────────────────────────────
        [iconView, titleLabel, subtitleLabel,
         cardView, allSetLabel, openSettingsBtn, hintLabel].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 52),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cardView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 40),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            enabledRow.topAnchor.constraint(equalTo: cardView.topAnchor),
            enabledRow.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            enabledRow.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            enabledRow.heightAnchor.constraint(equalToConstant: 54),

            divider.topAnchor.constraint(equalTo: enabledRow.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            divider.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            fullAccessRow.topAnchor.constraint(equalTo: divider.bottomAnchor),
            fullAccessRow.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            fullAccessRow.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            fullAccessRow.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            fullAccessRow.heightAnchor.constraint(equalToConstant: 54),

            allSetLabel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 20),
            allSetLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            openSettingsBtn.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 32),
            openSettingsBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            openSettingsBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            openSettingsBtn.heightAnchor.constraint(equalToConstant: 54),

            hintLabel.topAnchor.constraint(equalTo: openSettingsBtn.bottomAnchor, constant: 16),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }
}

// MARK: - StatusRowView

private final class StatusRowView: UIView {

    private let iconView  = UIImageView()
    private let textLabel = UILabel()
    private let badge     = UIView()
    private let badgeIcon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .secondaryLabel
        iconView.translatesAutoresizingMaskIntoConstraints = false

        textLabel.font = .systemFont(ofSize: 17)
        textLabel.textColor = .label
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        badge.layer.cornerRadius = 12
        badge.translatesAutoresizingMaskIntoConstraints = false

        badgeIcon.contentMode = .scaleAspectFit
        badgeIcon.tintColor = .white
        badgeIcon.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(badgeIcon)

        [iconView, textLabel, badge].forEach { addSubview($0) }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            textLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),

            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 24),
            badge.heightAnchor.constraint(equalToConstant: 24),

            badgeIcon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            badgeIcon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            badgeIcon.widthAnchor.constraint(equalToConstant: 13),
            badgeIcon.heightAnchor.constraint(equalToConstant: 13),
        ])
    }

    func configure(icon: String, title: String, isGranted: Bool) {
        iconView.image       = UIImage(systemName: icon)
        textLabel.text       = title
        badge.backgroundColor = isGranted ? .systemGreen : .systemRed
        badgeIcon.image      = UIImage(systemName: isGranted ? "checkmark" : "xmark")
    }
}
