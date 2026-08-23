//
//  FeaturedComponents.swift
//  AltStore
//
//  Created by Riley Testut on 12/4/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

class LargeIconCollectionViewCell: UICollectionViewCell
{
    let textLabel = UILabel(frame: .zero)
    let imageView = UIImageView(frame: .zero)
    
    override init(frame: CGRect)
    {
        self.textLabel.translatesAutoresizingMaskIntoConstraints = false
        self.textLabel.textColor = .white
        self.textLabel.font = .preferredFont(forTextStyle: .headline)
        
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.contentMode = .center
        self.imageView.tintColor = .white
        self.imageView.alpha = 0.4
        self.imageView.preferredSymbolConfiguration = .init(pointSize: 80)
        
        super.init(frame: frame)
        
        self.contentView.clipsToBounds = true
        self.contentView.layer.cornerRadius = 16
        self.contentView.layer.cornerCurve = .continuous
        
        self.contentView.addSubview(self.textLabel)
        self.contentView.addSubview(self.imageView)
        
        NSLayoutConstraint.activate([
            self.textLabel.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor, constant: 4),
            self.textLabel.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor, constant: -4),
            
            self.imageView.centerXAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -30),
            self.imageView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor, constant: 0),
            self.imageView.heightAnchor.constraint(equalTo: self.contentView.heightAnchor, constant: 0),
            self.imageView.widthAnchor.constraint(equalTo: self.imageView.heightAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class IconButtonCollectionReusableView: UICollectionReusableView
{
    let iconButton: UIButton
    let titleButton: UIButton
    
    private let stackView: UIStackView
    
    override init(frame: CGRect)
    {
        let iconHeight = 26.0
        
        self.iconButton = UIButton(type: .custom)
        self.iconButton.translatesAutoresizingMaskIntoConstraints = false
        self.iconButton.clipsToBounds = true
        self.iconButton.layer.cornerRadius = iconHeight / 2
        
        let content = UIListContentConfiguration.plainHeader()
        self.titleButton = UIButton(type: .system)
        self.titleButton.translatesAutoresizingMaskIntoConstraints = false
        self.titleButton.titleLabel?.font = content.textProperties.font
        self.titleButton.setTitleColor(content.textProperties.color, for: .normal)
        
        self.stackView = UIStackView(arrangedSubviews: [self.iconButton, self.titleButton])
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.stackView.axis = .horizontal
        self.stackView.alignment = .center
        self.stackView.spacing = UIStackView.spacingUseSystem
        self.stackView.isLayoutMarginsRelativeArrangement = false
        
        super.init(frame: frame)
        
        self.addSubview(self.stackView)
        
        NSLayoutConstraint.activate([
            self.iconButton.heightAnchor.constraint(equalToConstant: iconHeight),
            self.iconButton.widthAnchor.constraint(equalTo: self.iconButton.heightAnchor),
            
            self.stackView.topAnchor.constraint(equalTo: self.topAnchor),
            self.stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// 发现页顶部的引导卡片。免费 Apple 账号一台设备只能同时装 3 个自签应用,
// 装进西瓜多开的应用共用它那一个名额。但在列表里西瓜多开只是第一行,没人
// 知道为什么该先点它 —— 用户往往先装了别的,占满 3 个才发现装不下。
//
// 「全部应用」这个小标题也画在这张视图里:同一 alignment 的两个 boundary
// supplementary item 是按估算高度排位的,自适应长高之后不会重排,标题会压在
// 卡片上。所以显示这张卡片时,整段顶部只挂这一个 item。
class ContainerTipReusableView: UICollectionReusableView
{
    enum State
    {
        /// 还没装西瓜多开:整张卡片可点,点了去它的详情页。
        case recommendInstall
        /// 已经装了:降级成一条常驻说明,提醒后续应用往容器里装,不再可点。
        case recommendContainer
    }
    
    var tapHandler: (() -> Void)?
    
    var sectionTitle: String? {
        get { self.sectionTitleLabel.text }
        set { self.sectionTitleLabel.text = newValue }
    }
    
    private let cardView = UIView()
    private let contentStackView = UIStackView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let actionStackView = UIStackView()
    private let actionLabel = UILabel()
    private let chevronView = UIImageView()
    private let tapButton = UIButton(type: .custom)
    private let sectionTitleLabel = UILabel()
    
    private var state: State = .recommendInstall
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.cardView.translatesAutoresizingMaskIntoConstraints = false
        self.cardView.backgroundColor = .tertiarySystemBackground
        self.cardView.layer.cornerRadius = 16
        self.cardView.layer.cornerCurve = .continuous
        self.cardView.layer.borderWidth = 1
        self.addSubview(self.cardView)
        
        self.titleLabel.font = .preferredFont(forTextStyle: .headline)
        self.titleLabel.adjustsFontForContentSizeCategory = true
        self.titleLabel.numberOfLines = 0
        
        self.bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        self.bodyLabel.adjustsFontForContentSizeCategory = true
        self.bodyLabel.numberOfLines = 0
        self.bodyLabel.textColor = .secondaryLabel
        
        self.actionLabel.font = .preferredFont(forTextStyle: .subheadline)
        self.actionLabel.adjustsFontForContentSizeCategory = true
        self.actionLabel.numberOfLines = 0
        self.actionLabel.textColor = .systemGreen
        self.actionLabel.text = NSLocalizedString("Install it now", comment: "")
        
        self.chevronView.image = UIImage(systemName: "chevron.right")
        self.chevronView.tintColor = .systemGreen
        self.chevronView.contentMode = .scaleAspectFit
        self.chevronView.setContentHuggingPriority(.required, for: .horizontal)
        self.chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        self.actionStackView.axis = .horizontal
        self.actionStackView.alignment = .center
        self.actionStackView.spacing = 8
        self.actionStackView.addArrangedSubview(self.actionLabel)
        self.actionStackView.addArrangedSubview(self.chevronView)
        
        // 用 stack view 而不是一串 anchor:隐藏的 arranged subview 会自动收起,
        // 换状态时不用手动开关约束(隐藏的普通子视图仍然占约束链)。
        self.contentStackView.translatesAutoresizingMaskIntoConstraints = false
        self.contentStackView.axis = .vertical
        self.contentStackView.spacing = 6
        self.contentStackView.addArrangedSubview(self.titleLabel)
        self.contentStackView.addArrangedSubview(self.bodyLabel)
        self.contentStackView.addArrangedSubview(self.actionStackView)
        self.contentStackView.setCustomSpacing(10, after: self.bodyLabel)
        self.cardView.addSubview(self.contentStackView)
        
        // 整张卡片可点。用一个覆盖全卡的按钮而不是手势,免得和列表的滚动、
        // 以及复用时残留的手势打架。
        self.tapButton.translatesAutoresizingMaskIntoConstraints = false
        self.tapButton.addTarget(self, action: #selector(ContainerTipReusableView.didTap), for: .primaryActionTriggered)
        self.cardView.addSubview(self.tapButton)
        
        self.sectionTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        let titleFont = UIFont.preferredFont(forTextStyle: .title2)
        let boldDescriptor = titleFont.fontDescriptor.withSymbolicTraits(.traitBold) ?? titleFont.fontDescriptor
        self.sectionTitleLabel.font = UIFont(descriptor: boldDescriptor, size: 0)
        self.sectionTitleLabel.adjustsFontForContentSizeCategory = true
        self.sectionTitleLabel.numberOfLines = 0
        self.sectionTitleLabel.textColor = .label
        self.addSubview(self.sectionTitleLabel)
        
        self.accessibilityElements = [self.tapButton, self.sectionTitleLabel]
        
        NSLayoutConstraint.activate([
            self.cardView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.cardView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.cardView.topAnchor.constraint(equalTo: self.topAnchor),
            
            self.contentStackView.leadingAnchor.constraint(equalTo: self.cardView.leadingAnchor, constant: 16),
            self.contentStackView.trailingAnchor.constraint(equalTo: self.cardView.trailingAnchor, constant: -16),
            self.contentStackView.topAnchor.constraint(equalTo: self.cardView.topAnchor, constant: 14),
            self.contentStackView.bottomAnchor.constraint(equalTo: self.cardView.bottomAnchor, constant: -14),
            
            self.tapButton.leadingAnchor.constraint(equalTo: self.cardView.leadingAnchor),
            self.tapButton.trailingAnchor.constraint(equalTo: self.cardView.trailingAnchor),
            self.tapButton.topAnchor.constraint(equalTo: self.cardView.topAnchor),
            self.tapButton.bottomAnchor.constraint(equalTo: self.cardView.bottomAnchor),
            
            self.sectionTitleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.sectionTitleLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.sectionTitleLabel.topAnchor.constraint(equalTo: self.cardView.bottomAnchor, constant: 24),
            self.sectionTitleLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
        ])
        
        self.configure(with: .recommendInstall)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with state: State)
    {
        self.state = state
        
        switch state
        {
        case .recommendInstall:
            self.titleLabel.text = NSLocalizedString("Install XiguaContainer first", comment: "")
            self.bodyLabel.text = NSLocalizedString("A free Apple account can only run 3 sideloaded apps at once. Apps installed inside the container share its single slot, and one refresh renews them all.", comment: "")
            self.actionStackView.isHidden = false
            self.tapButton.isEnabled = true
            
        case .recommendContainer:
            self.titleLabel.text = NSLocalizedString("Install other apps inside XiguaContainer", comment: "")
            self.bodyLabel.text = NSLocalizedString("Open XiguaContainer and use its Library tab. Apps installed there don't use up your 3 sideloading slots, and refreshing the container renews them all at once.", comment: "")
            self.actionStackView.isHidden = true
            self.tapButton.isEnabled = false
        }
        
        self.tapButton.isAccessibilityElement = self.tapButton.isEnabled
        self.tapButton.accessibilityTraits = .button
        self.tapButton.accessibilityLabel = [self.titleLabel.text, self.bodyLabel.text, self.actionLabel.text].compactMap { $0 }.joined(separator: "。")
        
        self.updateBorderColor()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
    {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // cgColor 不跟随浅色/深色切换,得手动刷。
        self.updateBorderColor()
    }
    
    private func updateBorderColor()
    {
        let color: UIColor = switch self.state {
        case .recommendInstall: UIColor.systemGreen.withAlphaComponent(0.35)
        case .recommendContainer: .separator
        }
        
        self.cardView.layer.borderColor = color.resolvedColor(with: self.traitCollection).cgColor
    }
    
    @objc private func didTap()
    {
        self.tapHandler?()
    }
}
