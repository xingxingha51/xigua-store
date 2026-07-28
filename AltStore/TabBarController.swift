//
//  TabBarController.swift
//  AltStore
//
//  Created by Riley Testut on 9/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import AltStoreCore

extension TabBarController
{
    /// Raw values index into the storyboard's original ordering, which we keep
    /// hold of even for tabs that are hidden from the bar.
    private enum Tab: Int, CaseIterable
    {
        case news
        case sources
        case browse
        case myApps
        case settings

        /// Tabs the user actually sees. News is empty unless a source publishes
        /// announcements, and Sources is redundant now that ours is seeded
        /// automatically — both stay reachable in code, just not on the bar.
        static let visible: [Tab] = [.browse, .myApps, .settings]
    }
}

final class TabBarController: UITabBarController
{
    private var initialSegue: (identifier: String, sender: Any?)?
    
    private var _viewDidAppear = false
    
    private var sourcesViewController: SourcesViewController!

    /// The storyboard's full, unfiltered list, indexed by `Tab.rawValue`.
    private var allViewControllers: [UIViewController] = []

    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.importApp(_:)), name: AppDelegate.importAppDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.presentSources(_:)), name: AppDelegate.addSourceDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.exportFiles(_:)), name: AppDelegate.exportCertificateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.openErrorLog(_:)), name: ToastView.openErrorLogNotification, object: nil)
    }
    
    override func viewDidLoad() 
    {
        super.viewDidLoad()
        
        self.allViewControllers = self.viewControllers ?? []

        let browseNavigationController = self.allViewControllers[Tab.browse.rawValue] as! UINavigationController
        browseNavigationController.tabBarItem.image = UIImage(systemName: "bag")

        let sourcesNavigationController = self.allViewControllers[Tab.sources.rawValue] as! UINavigationController
        self.sourcesViewController = sourcesNavigationController.viewControllers.first as? SourcesViewController

        // Show only the tabs in Tab.visible. The hidden ones stay in
        // allViewControllers so deep links can still reach them.
        self.viewControllers = Tab.visible.map { self.allViewControllers[$0.rawValue] }
    }

    /// Position of a tab on the *visible* bar, or nil when it's hidden.
    private func selectedIndex(for tab: Tab) -> Int?
    {
        return Tab.visible.firstIndex(of: tab)
    }

    /// Switches to `tab`, or presents it modally when it isn't on the bar.
    private func show(_ tab: Tab)
    {
        if let index = self.selectedIndex(for: tab)
        {
            self.selectedIndex = index
            return
        }

        guard tab.rawValue < self.allViewControllers.count else { return }
        let viewController = self.allViewControllers[tab.rawValue]

        // A hidden tab has no bar to get back to, so give the modal an explicit
        // way out — otherwise a deep link would strand the user here.
        if let navigationController = viewController as? UINavigationController,
           let root = navigationController.viewControllers.first,
           root.navigationItem.leftBarButtonItem == nil
        {
            root.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                                    target: self,
                                                                    action: #selector(TabBarController.dismissPresentedTab))
        }

        self.present(viewController, animated: true, completion: nil)
    }

    @objc private func dismissPresentedTab()
    {
        self.dismiss(animated: true, completion: nil)
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        _viewDidAppear = true
        
        if let (identifier, sender) = self.initialSegue
        {
            self.initialSegue = nil
            self.performSegue(withIdentifier: identifier, sender: sender)
        }
    }
    
    override func performSegue(withIdentifier identifier: String, sender: Any?)
    {
        guard _viewDidAppear else {
            self.initialSegue = (identifier, sender)
            return
        }
        
        super.performSegue(withIdentifier: identifier, sender: sender)
    }
}

extension TabBarController
{
    @objc func presentSources(_ sender: Any)
    {
        if let presentedViewController = self.presentedViewController
        {
            presentedViewController.dismiss(animated: true) {
                self.presentSources(sender)
            }
            
            return
        }
                
        if let notification = (sender as? Notification), let sourceURL = notification.userInfo?[AppDelegate.addSourceDeepLinkURLKey] as? URL
        {
            self.sourcesViewController?.deepLinkSourceURL = sourceURL
        }
        
        self.show(.sources)
    }
}

private extension TabBarController
{
    @objc func importApp(_ notification: Notification)
    {
        self.show(.myApps)
    }

    @objc func openErrorLog(_ notification: Notification)
    {
        self.show(.settings)
    }
    
    @objc func exportFiles(_ notification: Notification)
    {
        self.show(.settings)
    }
}
