//
//  SettingsHeaderFooterView.swift
//  AltStore
//
//  Created by Riley Testut on 8/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit


final class SettingsHeaderFooterView: UITableViewHeaderFooterView
{
    @IBOutlet var primaryLabel: UILabel!
    @IBOutlet var secondaryLabel: UILabel!
    @IBOutlet var button: UIButton!
        
    @IBOutlet private var stackView: UIStackView!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentView.layoutMargins = .zero
        self.contentView.preservesSuperviewLayoutMargins = true

        // 分区标题跟上另外两页:发现页用系统的 prominentInsetGroupedHeader
        // (title2 粗体、label 色),我的应用是 24pt 粗体。设置页原本 14pt 灰色
        // 小字,三个 tab 里就它像另一个 App。footer 那个 secondaryLabel 不动,
        // 说明文字本来就该是小号灰色。
        let descriptor = UIFont.preferredFont(forTextStyle: .title2).fontDescriptor
        self.primaryLabel.font = UIFont(descriptor: descriptor.withSymbolicTraits(.traitBold) ?? descriptor, size: 0)
        self.primaryLabel.textColor = .label
        self.primaryLabel.adjustsFontForContentSizeCategory = true

        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.stackView)
        
        NSLayoutConstraint.activate([self.stackView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
                                     self.stackView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
                                     self.stackView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor),
                                     self.stackView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor)])
    }
}
