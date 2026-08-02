//
//  InsetGroupTableViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 8/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension InsetGroupTableViewCell
{
    @objc enum Style: Int
    {
        case single
        case top
        case middle
        case bottom
    }
}

final class InsetGroupTableViewCell: UITableViewCell
{
#if !TARGET_INTERFACE_BUILDER
    @IBInspectable var style: Style = .single {
        didSet {
            self.update()
        }
    }
#else
    @IBInspectable var style: Int = 0
#endif
    
    @IBInspectable var isSelectable: Bool = false

    private let separatorView = UIView()
    private let insetView = UIView()
    /// 按下时盖上去的一层。用 systemFill 而不是算颜色:它在深浅两种模式下
    /// 自己会反过来(浅色偏黑、深色偏白),不用两套值。
    private let highlightView = UIView()

    /// Interface Builder 上设的颜色(tertiarySystemBackground)。存下来是因为
    /// 按下态要能还原——之前这里直接把颜色写死,还原不回去。
    private var baseBackgroundColor: UIColor = .tertiarySystemBackground

    override func awakeFromNib()
    {
        super.awakeFromNib()

        self.selectionStyle = .none

        self.separatorView.translatesAutoresizingMaskIntoConstraints = false
        self.separatorView.backgroundColor = .separator
        self.addSubview(self.separatorView)

        self.insetView.layer.masksToBounds = true
        // 22 = AppBannerView 的圆角。发现页和我的应用的卡片都是这个数,
        // 设置页原本是 16,并排看就像两个 App。
        self.insetView.layer.cornerRadius = 22

        // Get the preferred background color from Interface Builder.
        self.baseBackgroundColor = self.backgroundColor ?? .tertiarySystemBackground
        self.insetView.backgroundColor = self.baseBackgroundColor
        self.backgroundColor = nil

        // 15 → 16:另外两页的卡片用的是 view.layoutMargins,iPhone 上就是 16。
        self.addSubview(self.insetView, pinningEdgesWith: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16))
        self.sendSubviewToBack(self.insetView)

        self.highlightView.backgroundColor = .systemFill
        self.highlightView.alpha = 0
        self.highlightView.isUserInteractionEnabled = false
        self.insetView.addSubview(self.highlightView, pinningEdgesWith: .zero)

        NSLayoutConstraint.activate([self.separatorView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 32),
                                     self.separatorView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -32),
                                     self.separatorView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                                     self.separatorView.heightAnchor.constraint(equalToConstant: 1 / UITraitCollection.current.displayScale)])

        self.update()
    }
    
    override func setSelected(_ selected: Bool, animated: Bool)
    {
        super.setSelected(selected, animated: animated)
        
        if animated
        {
            UIView.animate(withDuration: 0.4) {
                self.update()
            }
        }
        else
        {
            self.update()
        }
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool)
    {
        super.setHighlighted(highlighted, animated: animated)
        
        if animated
        {
            UIView.animate(withDuration: 0.4) {
                self.update()
            }
        }
        else
        {
            self.update()
        }
    }
}

private extension InsetGroupTableViewCell
{
    func update()
    {
        switch self.style
        {
        case .single:
            self.insetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            self.separatorView.isHidden = true
            
        case .top:
            self.insetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            self.separatorView.isHidden = false
            
        case .middle:
            self.insetView.layer.maskedCorners = []
            self.separatorView.isHidden = false
            
        case .bottom:
            self.insetView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            self.separatorView.isHidden = true
        }
        
        // 背景保持 Interface Builder 上那个 tertiarySystemBackground(浅色白、
        // 深色 #2C2C2E),按下只是盖一层。原本这里两种状态都写死成半透明白,
        // 那是上游紫色渐变背景下的做法:换到我们的背景上,浅色几乎看不见,
        // 深色又比另外两页的卡片亮一大截。
        self.insetView.backgroundColor = self.baseBackgroundColor
        self.highlightView.alpha = (self.isSelectable && (self.isHighlighted || self.isSelected)) ? 1 : 0
    }
}
