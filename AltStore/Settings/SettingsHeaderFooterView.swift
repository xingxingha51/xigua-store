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
        
        // 左右改用固定的 16,和卡片的缩进对齐。grouped 表头的 layoutMargins 是
        // 双倍缩进(约 32),标题会比它下面那张卡还往里，三个 tab 摆一起就数它
        // 的左边不齐。我的应用那页是大标题、分区标题、卡片全部齐平,照它。
        // 上下仍走 layoutMarginsGuide —— prepare(_:for:isHeader:) 靠改 bottom
        // 来区分表头和脚注的间距。
        NSLayoutConstraint.activate([self.stackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16),
                                     self.stackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16),
                                     self.stackView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor),
                                     self.stackView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor)])
    }
}
