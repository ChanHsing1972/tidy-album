import UIKit

@MainActor
final class CleaningCompletionPageView: UIView {
    // MARK: - UI Elements
    private let statusStack = UIStackView()
    // 1. 换成专门的 CircleContainer，确保任何情况下都是正圆
    private let statusCircleContainer = StatusCircleView()
    private let checkmarkView = UIImageView()
    private let textStack = UIStackView()
    private let titleLabel = UILabel()
    private let progressLabel = UILabel()
    
    private let actionStack = UIStackView()
    private let primaryButton = CleaningPressButton(type: .custom)
    private let secondaryButton = CleaningPressButton(type: .custom)
    
    // MARK: - Callbacks & States
    private var onPrimary: (() -> Void)?
    private var onSecondary: (() -> Void)?
    private var isActive = false
    private var activationAnimator: UIViewPropertyAnimator?

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupConstraints()
        applyInactiveState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup
    private func setupUI() {
        backgroundColor = .clear

        // 1. Status Stack Section
        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 16
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusStack)

        // Circle Container
        statusCircleContainer.translatesAutoresizingMaskIntoConstraints = false
        statusStack.addArrangedSubview(statusCircleContainer)

        // Checkmark Icon
        let checkmarkConfig = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
        checkmarkView.image = UIImage(systemName: "checkmark", withConfiguration: checkmarkConfig)
        checkmarkView.tintColor = .white
        checkmarkView.contentMode = .center
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        statusCircleContainer.addSubview(checkmarkView)

        // Labels Stack
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = 8
        statusStack.addArrangedSubview(textStack)

        // Title Label
        if let descriptor = UIFont.systemFont(ofSize: 28, weight: .bold).fontDescriptor.withDesign(.rounded) {
            titleLabel.font = UIFont(descriptor: descriptor, size: 28)
        } else {
            titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        }
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        textStack.addArrangedSubview(titleLabel)

        // Progress Label
        progressLabel.font = .systemFont(ofSize: 15, weight: .regular)
        progressLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        progressLabel.textAlignment = .center
        progressLabel.numberOfLines = 0
        textStack.addArrangedSubview(progressLabel)

        // 2. Action Stack Section
        actionStack.axis = .vertical
        actionStack.alignment = .fill
        actionStack.spacing = 10
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionStack)

        // Primary Button
        primaryButton.setTitleColor(.black, for: .normal)
        primaryButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        primaryButton.backgroundColor = .white
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        actionStack.addArrangedSubview(primaryButton)

        // Secondary Button
        secondaryButton.setTitleColor(UIColor.white.withAlphaComponent(0.65), for: .normal)
        secondaryButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        secondaryButton.backgroundColor = .clear
        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
        actionStack.addArrangedSubview(secondaryButton)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Status Stack Constraints
            statusStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -50),
            statusStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            statusStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),

            // Circle Container (宽高相等且固定 100)
            statusCircleContainer.widthAnchor.constraint(equalToConstant: 100),
            statusCircleContainer.heightAnchor.constraint(equalTo: statusCircleContainer.widthAnchor),

            // Checkmark Icon Constraints 居中在圆环内
            checkmarkView.centerXAnchor.constraint(equalTo: statusCircleContainer.centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: statusCircleContainer.centerYAnchor),

            // Labels Max Width
            textStack.widthAnchor.constraint(lessThanOrEqualToConstant: 300),

            // Action Stack Constraints
            actionStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            actionStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            actionStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
            actionStack.topAnchor.constraint(greaterThanOrEqualTo: statusStack.bottomAnchor, constant: 28),

            // Button Heights
            primaryButton.heightAnchor.constraint(equalToConstant: 54),
            secondaryButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    // MARK: - Public Configuration
    func configure(
        content: CleaningCompletionContent,
        onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void
    ) {
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        
        titleLabel.text = content.title
        progressLabel.text = content.progressText
        progressLabel.isHidden = (content.progressText == nil)
        
        primaryButton.setTitle(content.primaryTitle, for: .normal)
        secondaryButton.setTitle(content.secondaryTitle, for: .normal)
        secondaryButton.isHidden = (content.secondaryTitle == nil)
        
        primaryButton.accessibilityLabel = content.primaryTitle
        secondaryButton.accessibilityLabel = content.secondaryTitle
        accessibilityLabel = [content.title, content.progressText].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: - State & Animations
    func setActive(_ active: Bool, animated: Bool) {
        guard active != isActive else { return }
        isActive = active
        
        activationAnimator?.stopAnimation(true)
        
        let changes = {
            self.statusStack.alpha = active ? 1.0 : 0.0
            self.actionStack.alpha = active ? 1.0 : 0.0
            self.statusStack.transform = active ? .identity : CGAffineTransform(translationX: 0, y: 14)
            self.actionStack.transform = active ? .identity : CGAffineTransform(translationX: 0, y: 14)
            // 圆环背景缩放动画
            self.statusCircleContainer.transform = active ? .identity : CGAffineTransform(scaleX: 0.85, y: 0.85)
        }
        
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            UIView.performWithoutAnimation(changes)
            return
        }
        
        let animator = UIViewPropertyAnimator(duration: 0.45, timingParameters: UICubicTimingParameters(controlPoint1: CGPoint(x: 0.2, y: 1), controlPoint2: CGPoint(x: 0.2, y: 1)))
        animator.addAnimations(changes)
        activationAnimator = animator
        animator.startAnimation()
    }

    private func applyInactiveState() {
        statusStack.alpha = 0.0
        actionStack.alpha = 0.0
        statusStack.transform = CGAffineTransform(translationX: 0, y: 14)
        actionStack.transform = CGAffineTransform(translationX: 0, y: 14)
        statusCircleContainer.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
    }

    // MARK: - Actions
    @objc private func primaryTapped() {
        onPrimary?()
    }

    @objc private func secondaryTapped() {
        onSecondary?()
    }
}

// MARK: - Circle Background View
@MainActor
private final class StatusCircleView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.06)
        layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        layer.borderWidth = 3.0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 关键所在：在 Auto Layout 布局确定尺寸后，动态计算高度的一半作为 cornerRadius
        // 确保无论屏幕尺寸怎么变，这里都必定渲染成正圆形
        layer.cornerRadius = bounds.height / 2
    }
}

// MARK: - Press Button
@MainActor
private final class CleaningPressButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
                    self.alpha = self.isHighlighted ? 0.85 : 1.0
                }
            )
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.cornerCurve = .continuous
    }
}
