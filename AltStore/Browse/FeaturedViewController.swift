//
//  FeaturedViewController.swift
//  AltStore
//
//  Created by Riley Testut on 11/8/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import CoreData
import AltStoreCore

import Nuke

extension UIAction.Identifier
{
    fileprivate static let showAllApps = Self("io.sidestore.ShowAllApps")
    fileprivate static let showSourceDetails = Self("io.sidestore.ShowSourceDetails")
}

extension FeaturedViewController
{
    // Open-ended because each Source is its own section
    private struct Section: RawRepresentable, Equatable
    {
        // The page is one list now. Categories were a screen of navigation to
        // near-empty results, and the per-source "Featured" carousels below
        // repeated the very same apps as oversized cards.
        static let allApps = Section(rawValue: 0)
        
        let rawValue: Int
        
        init(rawValue: Int)
        {
            self.rawValue = rawValue
        }
    }
    
    private enum ReuseID: String
    {
        case recent = "RecentCell"
        case category = "CategoryCell"
        case featuredApp = "FeaturedAppCell"
    }
    
    private enum ElementKind: String
    {
        case sectionHeader
        case sourceHeader
        case button
        case containerTip
    }
}

class FeaturedViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    private lazy var recentlyUpdatedDataSource = self.makeRecentlyUpdatedDataSource()
    private lazy var featuredAppsDataSource = self.makeFeaturedAppsDataSource()
    
    private var searchController: RSTSearchController!
    private var searchBrowseViewController: BrowseViewController!
    
    // 免费账号一台设备只能同时装 3 个自签应用。装进西瓜多开的应用共用它那一个
    // 名额,所以第一件事应该是装西瓜多开 —— 但列表里它只是第一行,没人知道
    // 为什么该先点它,往往先装了别的,占满 3 个才发现装不下。
    // 装好之后卡片不消失,换成一条常驻说明,提醒后续应用往容器里装。
    private static let containerBundleID = "com.kdt.livecontainer"
    private var containerTipState: ContainerTipReusableView.State?
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Browse", comment: "")
        
        self.containerTipState = self.computeContainerTipState()
        NotificationCenter.default.addObserver(self, selector: #selector(FeaturedViewController.managedObjectContextDidChange(_:)),
                                               name: .NSManagedObjectContextObjectsDidChange, object: DatabaseManager.shared.viewContext)
        
        let layout = self.makeLayout()
        self.collectionView.collectionViewLayout = layout
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.collectionView.register(AppBannerCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.recent.rawValue)
        self.collectionView.register(LargeIconCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.category.rawValue)
        self.collectionView.register(AppCardCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.featuredApp.rawValue)
        
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: ElementKind.sectionHeader.rawValue, withReuseIdentifier: ElementKind.sectionHeader.rawValue)
        self.collectionView.register(IconButtonCollectionReusableView.self, forSupplementaryViewOfKind: ElementKind.sourceHeader.rawValue, withReuseIdentifier: ElementKind.sourceHeader.rawValue)
        self.collectionView.register(ButtonCollectionReusableView.self, forSupplementaryViewOfKind: ElementKind.button.rawValue, withReuseIdentifier: ElementKind.button.rawValue)
        self.collectionView.register(ContainerTipReusableView.self, forSupplementaryViewOfKind: ElementKind.containerTip.rawValue, withReuseIdentifier: ElementKind.containerTip.rawValue)
        
        self.collectionView.backgroundColor = .altBackground
        self.collectionView.directionalLayoutMargins.leading = 20
        self.collectionView.directionalLayoutMargins.trailing = 20
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        self.searchBrowseViewController = storyboard.instantiateViewController(identifier: "browseViewController") { coder in
            let browseViewController = BrowseViewController(coder: coder)
            return browseViewController
        }
        
        self.searchController = RSTSearchController(searchResultsController: self.searchBrowseViewController)
        self.searchController.searchableKeyPaths = [#keyPath(StoreApp.name),
                                                    #keyPath(StoreApp.developerName),
                                                    #keyPath(StoreApp.subtitle),
                                                    #keyPath(StoreApp.bundleIdentifier)]
        self.searchController.searchHandler = { [weak searchBrowseViewController] (searchValue, _) in
            searchBrowseViewController?.searchPredicate = searchValue.predicate
            return nil
        }
        
        self.navigationItem.searchController = self.searchController
        self.navigationItem.hidesSearchBarWhenScrolling = true
        
        self.navigationItem.largeTitleDisplayMode = .always
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.updateContainerTip()
    }
    
    override func viewDidAppear(_ animated: Bool) 
    {
        super.viewDidAppear(animated)
        
        self.navigationController?.navigationBar.tintColor = .altPrimary
    }
}

extension FeaturedViewController
{
    @objc fileprivate func managedObjectContextDidChange(_ notification: Notification)
    {
        // 不在通知里同步动 UI:此刻 FRC 可能正在处理同一批变更。
        DispatchQueue.main.async { self.updateContainerTip() }
    }
}

private extension FeaturedViewController
{
    func computeContainerTipState() -> ContainerTipReusableView.State?
    {
        let context = DatabaseManager.shared.viewContext
        
        // InstalledApp.bundleIdentifier 存的是原始 bundle id(重签后的在
        // resignedBundleIdentifier),所以这里能直接比。不走 storeApp.installedApp:
        // 用户可能是从别处装的西瓜多开,那条关系不一定连上。
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), Self.containerBundleID)
        guard InstalledApp.first(satisfying: predicate, in: context) == nil else { return .recommendContainer }
        
        // 还没装,但源也还没拉下来 —— 没有可跳转的目标,先不显示。一张点不动
        // 的卡片比没有卡片更糟。
        guard self.containerStoreApp(in: context) != nil else { return nil }
        return .recommendInstall
    }
    
    func containerStoreApp(in context: NSManagedObjectContext) -> StoreApp?
    {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(StoreApp.bundleIdentifier), Self.containerBundleID)
        return StoreApp.first(satisfying: predicate, in: context)
    }
    
    func updateContainerTip()
    {
        let containerTipState = self.computeContainerTipState()
        guard containerTipState != self.containerTipState else { return }
        
        self.containerTipState = containerTipState
        
        // 先改状态再 invalidate:sectionProvider 要读新值来决定挂不挂这个 item。
        self.collectionView.collectionViewLayout.invalidateLayout()
        
        // 从「建议安装」换到「建议装进容器」时 item 还在,invalidateLayout
        // 不会重新 dequeue,得自己把文案换掉。
        guard let containerTipState else { return }
        for view in self.collectionView.visibleSupplementaryViews(ofKind: ElementKind.containerTip.rawValue)
        {
            (view as? ContainerTipReusableView)?.configure(with: containerTipState)
        }
    }
    
    func showContainerApp()
    {
        guard let storeApp = self.containerStoreApp(in: DatabaseManager.shared.viewContext) else { return }
        
        let appViewController = AppViewController.makeAppViewController(app: storeApp)
        self.navigationController?.pushViewController(appViewController, animated: true)
    }
    
    // 实例方法而非 class func:sectionProvider 要读 containerTipState。
    // 装完西瓜多开只需 invalidateLayout(),不用重建整个布局对象。
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 0
        config.contentInsetsReference = .layoutMargins
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            let section = Section(rawValue: sectionIndex)
            
            let spacing = 10.0
            let interSectionSpacing = 30.0
            let titleSize = NSCollectionLayoutSize(widthDimension: .estimated(100), heightDimension: .estimated(30))
            
            switch section
            {
            case .allApps:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(AppBannerView.standardHeight))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                // One per row, scrolling with the page — a horizontal pager hid
                // most of the list behind a swipe nobody discovers.
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(AppBannerView.standardHeight))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = spacing
                layoutSection.orthogonalScrollingBehavior = .none
                layoutSection.contentInsets.bottom = interSectionSpacing
                // 顶部只挂一个 boundary item:引导卡片那份自带「全部应用」标题。
                // 两个同 alignment 的 item 会按估算高度排位,自适应长高后不重排。
                if self?.containerTipState != nil
                {
                    let tipSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(220))
                    layoutSection.boundarySupplementaryItems = [
                        NSCollectionLayoutBoundarySupplementaryItem(layoutSize: tipSize, elementKind: ElementKind.containerTip.rawValue, alignment: .topLeading)
                    ]
                }
                else
                {
                    layoutSection.boundarySupplementaryItems = [
                        NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.sectionHeader.rawValue, alignment: .topLeading)
                    ]
                }
                return layoutSection
                
            default: return nil
            }
        }, configuration: config)
        
        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>(dataSources: [self.recentlyUpdatedDataSource])
        dataSource.predicate = StoreApp.visibleAppsPredicate // Ensure we never accidentally show hidden apps
        return dataSource
    }
    
    func makeRecentlyUpdatedDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let fetchRequest = StoreApp.fetchRequest() as NSFetchRequest<StoreApp>
        fetchRequest.returnsObjectsAsFaults = false
        // Source order, not release date. This is now the page's only list, so
        // whoever maintains apps.json decides what a new user sees first —
        // LiveContainer, because everything else can then share its one slot.
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \StoreApp.sortIndex, ascending: true),
            NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
            NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true),
            NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true),
        ]
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellIdentifierHandler = { _ in ReuseID.recent.rawValue }
        dataSource.liveFetchLimit = 10 // Show 10 most recently updated apps
        dataSource.cellConfigurationHandler = { cell, storeApp, indexPath in
            let cell = cell as! AppBannerCollectionViewCell
            cell.tintColor = storeApp.tintColor
            cell.contentView.preservesSuperviewLayoutMargins = false
            cell.contentView.layoutMargins = .zero
            
            cell.bannerView.button.isIndicatingActivity = false
            cell.bannerView.configure(for: storeApp)
            
            if let versionDate = storeApp.latestSupportedVersion?.date
            {
                cell.bannerView.subtitleLabel.text = Date().relativeDateString(since: versionDate, dateFormatter: Date.mediumDateFormatter)
            }
            
            cell.bannerView.button.addTarget(self, action: #selector(FeaturedViewController.performAppAction), for: .primaryActionTriggered)
            
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
        }
        dataSource.prefetchHandler = { (storeApp, indexPath, completion) -> Foundation.Operation? in
            return RSTAsyncBlockOperation { (operation) in
                storeApp.managedObjectContext?.perform {
                    ImagePipeline.shared.loadImage(with: storeApp.iconURL, progress: nil) { result in
                        guard !operation.isCancelled else { return operation.finish() }
                        
                        switch result
                        {
                        case .success(let response): completion(response.image, nil)
                        case .failure(let error): completion(nil, error)
                        }
                    }
                }
            }
        }
        dataSource.prefetchCompletionHandler = { [weak dataSource] (cell, image, indexPath, error) in
            let cell = cell as! AppBannerCollectionViewCell
            cell.bannerView.iconImageView.image = image
            cell.bannerView.iconImageView.isIndicatingActivity = false
            
            if let error, let dataSource
            {
                let app = dataSource.item(at: indexPath)
                debugLog("Failed to app icon from \(app.iconURL). \(error.localizedDescription)")
            }
        }
        
        return dataSource
    }
    
    
    func makeFeaturedAppsDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let fetchRequest = StoreApp.fetchRequest() as NSFetchRequest<StoreApp>
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.sortDescriptors = [
            // Sort by Source first to group into sections.
            NSSortDescriptor(keyPath: \StoreApp._source?.featuredSortID, ascending: true),
            
            // Show uninstalled apps first.
            // Sorting by StoreApp.installedApp crashes because InstalledApp does not respond to compare:
            // Instead, sort by StoreApp.installedApp.storeApp.source.sourceIdentifier, which will be either nil OR source ID.
            NSSortDescriptor(keyPath: \StoreApp.installedApp?.storeApp?.sourceIdentifier, ascending: true),
            
            // Show featured apps first.
            // Sorting by StoreApp.featuringSource crashes because Source does not respond to compare:
            // Instead, sort by StoreApp.featuringSource.identifier, which will be either nil OR source ID.
            NSSortDescriptor(keyPath: \StoreApp.featuringSource?.identifier, ascending: false),
            
            // Randomize order within sections.
            NSSortDescriptor(keyPath: \StoreApp.featuredSortID, ascending: true),
            
            // Sanity check to ensure stable ordering
            NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true)
        ]
        
        let sourceHasRemainingAppsPredicate = NSPredicate(format:
            """
            SUBQUERY(%K, $app,
                ($app.%K != %@) AND ($app.%K == nil)
            ).@count > 0
            """,
            #keyPath(StoreApp._source._apps),
            #keyPath(StoreApp.bundleIdentifier),
            StoreApp.altstoreAppID,
            #keyPath(StoreApp.installedApp)
        )
        
        let primaryFetchRequest = fetchRequest.copy() as! NSFetchRequest<StoreApp>
        primaryFetchRequest.predicate = sourceHasRemainingAppsPredicate
        
        let primaryController = NSFetchedResultsController(fetchRequest: primaryFetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(StoreApp._source.featuredSortID), cacheName: nil)
        let primaryDataSource = RSTFetchedResultsCollectionViewDataSource<StoreApp>(fetchedResultsController: primaryController)
        primaryDataSource.liveFetchLimit = 5
        
        let secondaryFetchRequest = fetchRequest.copy() as! NSFetchRequest<StoreApp>
        secondaryFetchRequest.predicate = NSCompoundPredicate(notPredicateWithSubpredicate: sourceHasRemainingAppsPredicate)
        
        let secondaryController = NSFetchedResultsController(fetchRequest: secondaryFetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(StoreApp._source.featuredSortID), cacheName: nil)
        let secondaryDataSource = RSTFetchedResultsCollectionViewDataSource<StoreApp>(fetchedResultsController: secondaryController)
        secondaryDataSource.liveFetchLimit = 5
        
        // Ensure sources with no remaining apps always come last.
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>(dataSources: [primaryDataSource, secondaryDataSource])
        dataSource.cellIdentifierHandler = { _ in ReuseID.featuredApp.rawValue }
        dataSource.cellConfigurationHandler = { cell, storeApp, indexPath in
            let cell = cell as! AppCardCollectionViewCell
            cell.configure(for: storeApp)
            cell.prefersPagingScreenshots = false
            
            cell.bannerView.button.addTarget(self, action: #selector(FeaturedViewController.performAppAction), for: .primaryActionTriggered)
            cell.bannerView.sourceIconImageView.isHidden = true
            
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
        }
        dataSource.prefetchHandler = { (storeApp, indexPath, completion) -> Foundation.Operation? in
            return RSTAsyncBlockOperation { (operation) in
                storeApp.managedObjectContext?.perform {
                    ImagePipeline.shared.loadImage(with: storeApp.iconURL, progress: nil) { result in
                        guard !operation.isCancelled else { return operation.finish() }
                        
                        switch result
                        {
                        case .success(let response): completion(response.image, nil)
                        case .failure(let error): completion(nil, error)
                        }
                    }
                }
            }
        }
        dataSource.prefetchCompletionHandler = { [weak dataSource] (cell, image, indexPath, error) in
            let cell = cell as! AppCardCollectionViewCell
            cell.bannerView.iconImageView.image = image
            cell.bannerView.iconImageView.isIndicatingActivity = false
            
            if let error = error, let dataSource
            {
                let app = dataSource.item(at: indexPath)
                debugLog("Failed to app icon from \(app.iconURL). \(error.localizedDescription)")
            }
        }
        
        return dataSource
    }
}

private extension FeaturedViewController
{
    @IBSegueAction
    func makeBrowseViewController(_ coder: NSCoder, sender: Any) -> UIViewController?
    {
        if let category = sender as? StoreCategory
        {
            let browseViewController = BrowseViewController(category: category, coder: coder)
            return browseViewController
        }
        else if let source = sender as? Source
        {
            let browseViewController = BrowseViewController(source: source, coder: coder)
            return browseViewController
        }
        else
        {
            let browseViewController = BrowseViewController(coder: coder)
            return browseViewController
        }
    }
    
    @IBSegueAction
    func makeSourceDetailViewController(_ coder: NSCoder, sender: Any?) -> UIViewController?
    {
        guard let source = sender as? Source else { return nil }
        
        let sourceDetailViewController = SourceDetailViewController(source: source, coder: coder)
        return sourceDetailViewController
    }
    
    func showAllApps(for source: Source)
    {
        self.performSegue(withIdentifier: "showBrowseViewController", sender: source)
    }
    
    func showSourceDetails(for source: Source)
    {
        self.performSegue(withIdentifier: "showSourceDetails", sender: source)
    }
}

private extension FeaturedViewController
{
    @objc func performAppAction(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let storeApp = self.dataSource.item(at: indexPath)
        
        // if let installedApp = storeApp.installedApp, !installedApp.isUpdateAvailable
        if let installedApp = storeApp.installedApp, !installedApp.hasUpdate
        {
            self.open(installedApp)
        } else
        {
            self.install(storeApp, at: indexPath) { progress in
                sender.progress = progress
            }
        }
    }
    
    func install(_ storeApp: StoreApp, at indexPath: IndexPath, progressUpdateHandler: @escaping (Progress) -> Void)
    {
        let previousProgress = AppManager.shared.installationProgress(for: storeApp)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        // if let installedApp = storeApp.installedApp, installedApp.isUpdateAvailable
        if let installedApp = storeApp.installedApp, installedApp.hasUpdate
        {
            let progress = AppManager.shared.update(installedApp, presentingViewController: self, completionHandler: finish(_:))
            progressUpdateHandler(progress)
        }
        else
        {
            let group = AppManager.shared.install(storeApp, presentingViewController: self, completionHandler: finish(_:))
            progressUpdateHandler(group.progress)
        }
        
        func finish(_ result: Result<InstalledApp, Error>)
        {
            DispatchQueue.main.async {
                switch result
                {
                case .failure(OperationError.cancelled): break // Ignore
                case .failure(let error):
                    let toastView = ToastView(error: error)
                    toastView.opensErrorLog = true
                    toastView.show(in: self)
                    
                case .success:
                    debugLog("Installed app \(storeApp.bundleIdentifier) from FeaturedViewController.")
                }
                
                for indexPath in self.collectionView.indexPathsForVisibleItems
                {
                    // Only need to reload if it's still visible.
                    
                    let item = self.dataSource.item(at: indexPath)
                    guard item == storeApp else { continue }
                    
                    UIView.performWithoutAnimation {
                        self.collectionView.reloadItems(at: [indexPath])
                    }
                }
            }
        }
    }
    
    func open(_ installedApp: InstalledApp)
    {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

extension FeaturedViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let section = Section(rawValue: indexPath.section)
        
        switch kind
        {
        case ElementKind.sourceHeader.rawValue:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! IconButtonCollectionReusableView
            
            let indexPath = IndexPath(item: 0, section: indexPath.section)
            let storeApp = self.dataSource.item(at: indexPath)
            
            var content = UIListContentConfiguration.plainHeader()
            content.text = storeApp.source?.name ?? NSLocalizedString("Unknown Source", comment: "")
            content.textProperties.numberOfLines = 1
            
            content.directionalLayoutMargins.leading = 0
            content.imageToTextPadding = 8
            content.imageProperties.reservedLayoutSize = CGSize(width: 26, height: 26)
            content.imageProperties.maximumSize = CGSize(width: 26, height: 26)
            content.imageProperties.cornerRadius = 13
            
            UIView.performWithoutAnimation {
                headerView.titleButton.setTitle(content.text, for: .normal)
                headerView.titleButton.layoutIfNeeded()
            }
            
            headerView.iconButton.backgroundColor = storeApp.source?.effectiveTintColor?.adjustedForDisplay
            headerView.iconButton.setImage(nil, for: .normal)
            
            if let iconURL = storeApp.source?.effectiveIconURL
            {
                ImagePipeline.shared.loadImage(with: iconURL) { result in
                    guard case .success(let image) = result else { return }

                    headerView.iconButton.backgroundColor = .white
                    headerView.iconButton.setImage(image.image, for: .normal)
                }
            }
            
            let buttons = [headerView.iconButton, headerView.titleButton]
            for button in buttons
            {
                button.removeAction(identifiedBy: .showSourceDetails, for: .primaryActionTriggered)
                
                if let source = storeApp.source
                {
                    let action = UIAction(identifier: .showSourceDetails) { [weak self] _ in
                        self?.showSourceDetails(for: source)
                    }
                    button.addAction(action, for: .primaryActionTriggered)
                }
            }
            
            return headerView
            
        case ElementKind.containerTip.rawValue:
            let tipView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! ContainerTipReusableView
            tipView.tapHandler = { [weak self] in self?.showContainerApp() }
            tipView.sectionTitle = NSLocalizedString("New & Updated", comment: "")
            tipView.configure(with: self.containerTipState ?? .recommendInstall)
            return tipView
            
        case ElementKind.sectionHeader.rawValue:
            // Regular section header
            
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! UICollectionViewListCell
            
            var content: UIListContentConfiguration = if #available(iOS 15, *) {
                .prominentInsetGroupedHeader()
            }
            else {
                .groupedHeader()
            }
            
            switch section
            {
            case .allApps: content.text = NSLocalizedString("New & Updated", comment: "")
            default: break
            }
            
            content.directionalLayoutMargins.leading = .zero
            content.directionalLayoutMargins.trailing = .zero
            
            headerView.contentConfiguration = content
            return headerView
            
        default: return UICollectionReusableView(frame: .zero)
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let storeApp = self.dataSource.item(at: indexPath)
        
        let section = Section(rawValue: indexPath.section)
        switch section
        {
        case .allApps:
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            self.navigationController?.pushViewController(appViewController, animated: true)
            
        default: break
        }
    }
}

@available(iOS 17, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
    
    let storyboard = UIStoryboard(name: "Main", bundle: nil)
    let featuredViewController = storyboard.instantiateViewController(identifier: "featuredViewController")
    
    let navigationController = UINavigationController(rootViewController: featuredViewController)
    navigationController.navigationBar.prefersLargeTitles = true
    navigationController.modalPresentationStyle = .fullScreen
    
    let viewController = UIViewController()
    
    AppManager.shared.fetchSources() { (result) in
        do
        {
            let (_, context) = try result.get()
            try context.save()
        }
        catch let error as NSError
        {
            debugLog("Failed to fetch sources for preview. \(error.localizedDescription)")
        }
    }
    
    AppManager.shared.updateKnownSources { result in
        Task {
            do
            {
                let knownSources = try result.get()
                
                let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                
                await withThrowingTaskGroup(of: Void.self) { taskGroup in
                    for source in knownSources.0
                    {
                        guard let sourceURL = source.sourceURL else { continue }
                        
                        taskGroup.addTask {
                            _ = try await AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context)
                        }
                    }
                }
                
                await context.performAsync {
                    try! context.save()
                }
                
                await MainActor.run {
                    viewController.present(navigationController, animated: true)
                }
            }
            catch
            {
                debugLog("Failed to fetch known sources for preview. \(error.localizedDescription)")
            }
        }
    }
    
    return viewController
}
