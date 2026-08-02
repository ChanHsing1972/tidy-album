import UIKit

@MainActor
final class CleaningCompletionPageView: UIView {
    private let statusStack = UIStackView()
    private let statusCircle = UIView()
    private let checkmarkView = UIImageView()
    private let titleLabel = UILabel()
    private let progressLabel = UILabel()
    private let actionStack = UIStackView()
    private let primaryButton = CleaningPressButton(type: .system)
    private let secondaryButton = CleaningPressButton(type: .system)
    private var onPrimary: (() -> Void)?
    private var onSecondary: (() -> Void)?
    private var isActive = false
    private var activationAnimator: UIViewPropertyAnimator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 20
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusStack)

        statusCircle.translatesAutoresizingMaskIntoConstraints = false
        statusCircle.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        statusCircle.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        statusCircle.layer.borderWidth = 6
        statusCircle.layer.shadowColor = UIColor.black.cgColor
        statusCircle.layer.shadowOpacity = 0.2
        statusCircle.layer.shadowRadius = 14
        statusCircle.layer.shadowOffset = CGSize(width: 0, height: 5)
        statusStack.addArrangedSubview(statusCircle)

        let checkmarkConfiguration = UIImage.SymbolConfiguration(pointSize: 38, weight: .bold)
        checkmarkView.image = UIImage(systemName: "checkmark", withConfiguration: checkmarkConfiguration)
        checkmarkView.tintColor = .white
        checkmarkView.contentMode = .center
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        statusCircle.addSubview(checkmarkView)

        let labels = UIStackView(arrangedSubviews: [titleLabel, progressLabel])
        labels.axis = .vertical
        labels.alignment = .center
        labels.spacing = 8
        statusStack.addArrangedSubview(labels)

        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.78

        progressLabel.font = .preferredFont(forTextStyle: .subheadline)
        progressLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        progressLabel.textAlignment = .center
        progressLabel.numberOfLines = 0

        actionStack.axis = .vertical
        actionStack.alignment = .center
        actionStack.spacing = 10
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionStack)
        actionStack.addArrangedSubview(primaryButton)
        actionStack.addArrangedSubview(secondaryButton)

        primaryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        var primaryConfiguration = UIButton.Configuration.plain()
        primaryConfiguration.baseForegroundColor = .black
        primaryConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: 20,
            bottom: 0,
            trailing: 20
        )
        primaryButton.configuration = primaryConfiguration
        primaryButton.backgroundColor = .white
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        secondaryButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        secondaryButton.setTitleColor(UIColor.white.withAlphaComponent(0.76), for: .normal)
        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            statusStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -54),
            statusStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 28),
            statusStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            statusCircle.widthAnchor.constraint(equalToConstant: 112),
            statusCircle.heightAnchor.constraint(equalToConstant: 112),
            checkmarkView.leadingAnchor.constraint(equalTo: statusCircle.leadingAnchor),
            checkmarkView.trailingAnchor.constraint(equalTo: statusCircle.trailingAnchor),
            checkmarkView.topAnchor.constraint(equalTo: statusCircle.topAnchor),
            checkmarkView.bottomAnchor.constraint(equalTo: statusCircle.bottomAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 324),
            progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 324),
            actionStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            actionStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            actionStack.topAnchor.constraint(greaterThanOrEqualTo: statusStack.bottomAnchor, constant: 32),
            primaryButton.heightAnchor.constraint(equalToConstant: 52),
            secondaryButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        statusCircle.layer.cornerRadius = 56
        statusCircle.layer.cornerCurve = .continuous
        statusCircle.layer.shadowPath = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 112, height: 112)).cgPath
        applyInactiveState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        content: CleaningCompletionContent,
        onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void
    ) {
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        titleLabel.text = content.title
        progressLabel.text = content.progressText
        progressLabel.isHidden = content.progressText == nil
        primaryButton.setTitle(content.primaryTitle, for: .normal)
        secondaryButton.setTitle(content.secondaryTitle, for: .normal)
        secondaryButton.isHidden = content.secondaryTitle == nil
        primaryButton.accessibilityLabel = content.primaryTitle
        secondaryButton.accessibilityLabel = content.secondaryTitle
        accessibilityLabel = [content.title, content.progressText].compactMap { $0 }.joined(separator: ", ")
    }

    func setActive(_ active: Bool, animated: Bool) {
        guard active != isActive else { return }
        isActive = active
        activationAnimator?.stopAnimation(true)
        let changes = {
            self.statusStack.alpha = active ? 1 : 0.82
            self.actionStack.alpha = active ? 1 : 0.82
            self.statusStack.transform = active ? .identity : CGAffineTransform(translationX: 0, y: 8)
            self.actionStack.transform = active ? .identity : CGAffineTransform(translationX: 0, y: 8)
            self.statusCircle.transform = active ? .identity : CGAffineTransform(scaleX: 0.82, y: 0.82)
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            UIView.performWithoutAnimation(changes)
            return
        }
        let animator = UIViewPropertyAnimator(duration: 0.45, dampingRatio: 1, animations: changes)
        activationAnimator = animator
        animator.startAnimation()
    }

    private func applyInactiveState() {
        statusStack.alpha = 0.82
        actionStack.alpha = 0.82
        statusStack.transform = CGAffineTransform(translationX: 0, y: 8)
        actionStack.transform = CGAffineTransform(translationX: 0, y: 8)
        statusCircle.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
    }

    @objc private func primaryTapped() {
        onPrimary?()
    }

    @objc private func secondaryTapped() {
        onSecondary?()
    }
}

@MainActor
private final class CleaningPressButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: 0.12,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    self.transform = self.isHighlighted
                        ? CGAffineTransform(scaleX: 0.97, y: 0.97)
                        : .identity
                    self.alpha = self.isHighlighted ? 0.88 : 1
                }
            )
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height * 0.5
        layer.cornerCurve = .continuous
    }
}
