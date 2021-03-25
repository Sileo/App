//
//  TabBarController.swift
//  Sileo
//
//  Created by CoolStar on 4/20/20.
//  Copyright © 2020 CoolStar. All rights reserved.
//

import Foundation
import LNPopupController

class TabBarController: UITabBarController, UITabBarControllerDelegate {
    static var singleton: TabBarController?
    private var downloadsController: UINavigationController?
    private var popupIsPresented = false
    private var popupLock = DispatchSemaphore(value: 1)
    private var shouldSelectIndex = -1
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        delegate = self
        TabBarController.singleton = self
        
        downloadsController = UINavigationController(rootViewController: DownloadManager.shared.viewController)
        downloadsController?.isNavigationBarHidden = true
        downloadsController?.popupItem.title = ""
        downloadsController?.popupItem.subtitle = ""
        
        weak var weakSelf = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        updateSileoColors()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.updatePopup()
    }
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        shouldSelectIndex = tabBarController.selectedIndex
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if shouldSelectIndex == tabBarController.selectedIndex {
            if let splitViewController = viewController as? UISplitViewController {
                if let navController = splitViewController.viewControllers[0] as? UINavigationController {
                    navController.popToRootViewController(animated: true)
                }
            }
        }
    }
    
    func presentPopup() {
        presentPopup(completion: nil)
    }
    
    func presentPopup(completion: (() -> Void)?) {
        guard let downloadsController = downloadsController else {
            return
        }
        if popupIsPresented {
            return
        }
        popupLock.wait()
        defer { popupLock.signal() }
        if popupIsPresented {
            return
        }
        popupIsPresented = true
        self.popupContentView.popupCloseButtonAutomaticallyUnobstructsTopBars = false
        self.popupBar.toolbar.tag = WHITE_BLUR_TAG
        self.popupBar.barStyle = .prominent
        
        self.updateSileoColors()
        
        self.popupBar.toolbar.setBackgroundImage(nil, forToolbarPosition: .any, barMetrics: .default)
        self.popupBar.isInlineWithTabBar = UIDevice.current.userInterfaceIdiom == .pad
        self.popupBar.tabBarHeight = self.tabBar.frame.height
        self.popupBar.progressViewStyle = .bottom
        self.popupInteractionStyle = .drag
        self.presentPopupBar(withContentViewController: downloadsController, animated: true, completion: completion)
        
        self.updateSileoColors()
    }
    
    func dismissPopup() {
        dismissPopup(completion: nil)
    }
    
    func dismissPopup(completion: (() -> Void)?) {
        guard popupIsPresented else {
            return
        }
        popupLock.wait()
        defer { popupLock.signal() }
        guard popupIsPresented else {
            return
        }
        popupIsPresented = false
        self.dismissPopupBar(animated: true, completion: completion)
    }
    
    func presentPopupController() {
        self.presentPopupController(completion: nil)
    }
    
    func dismissPopupController() {
        self.dismissPopupController(completion: nil)
    }
    
    func presentPopupController(completion: (() -> Void)?) {
        if popupIsPresented {
            return
        }
        
        popupLock.wait()
        defer {
            popupLock.signal()
        }
        
        self.openPopup(animated: true, completion: completion)
    }
    
    func dismissPopupController(completion: (() -> Void)?) {
        if popupIsPresented {
            return
        }
        
        popupLock.wait()
        defer {
            popupLock.signal()
        }
        
        self.closePopup(animated: true, completion: completion)
    }
    
    func updatePopup() {
        updatePopup(completion: nil)
    }
    
    func updatePopup(completion: (() -> Void)?) {
        let manager = DownloadManager.shared
        if manager.lockedForInstallation {
            downloadsController?.popupItem.title = String(localizationKey: "Installing_Package_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.readyPackages())
            downloadsController?.popupItem.progress = Float(manager.totalProgress)
            self.presentPopup(completion: completion)
        } else if manager.downloadingPackages() > 0 {
            downloadsController?.popupItem.title = String(localizationKey: "Downloading_Package_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.downloadingPackages())
            downloadsController?.popupItem.progress = 0
            self.presentPopup(completion: completion)
        } else if manager.queuedPackages() > 0 {
            downloadsController?.popupItem.title = String(localizationKey: "Queued_Package_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.queuedPackages())
            downloadsController?.popupItem.progress = 0
            self.presentPopup(completion: completion)
        } else if manager.readyPackages() > 0 {
            downloadsController?.popupItem.title = String(localizationKey: "Ready_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.readyPackages())
            downloadsController?.popupItem.progress = 0
            self.presentPopup(completion: completion)
        } else if manager.uninstallingPackages() > 0 {
            downloadsController?.popupItem.title = String(localizationKey: "Removal_Queued_Package_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.uninstallingPackages())
            downloadsController?.popupItem.progress = 0
            self.presentPopup(completion: completion)
        } else {
            if UIDevice.current.userInterfaceIdiom == .pad && self.view.frame.width >= 768 {
                downloadsController?.popupItem.title = String(localizationKey: "Queued_Package_Status")
                downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), 0)
                self.presentPopup(completion: completion)
            } else {
                self.dismissPopup(completion: completion)
            }
        }
    }
    
    override var bottomDockingViewForPopupBar: UIView? {
        self.tabBar
    }
    
    override var defaultFrameForBottomDockingView: CGRect {
        var tabBarFrame = self.tabBar.frame
        tabBarFrame.origin.y = self.view.bounds.height - tabBarFrame.height
        if UIDevice.current.userInterfaceIdiom == .pad {
            tabBarFrame.origin.x = 0
            tabBarFrame.size.width = self.view.bounds.width
            if tabBarFrame.width >= 768 {
                tabBarFrame.size.width -= 320
            }
        }
        return tabBarFrame
    }
    
    override var insetsForBottomDockingView: UIEdgeInsets {
        if UIDevice.current.userInterfaceIdiom == .pad {
            if self.view.bounds.width < 768 {
                return .zero
            }
            return UIEdgeInsets(top: self.tabBar.frame.height, left: self.view.bounds.width - 320, bottom: 0, right: 0)
        }
        return .zero
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateSileoColors()
    }
    
    @objc func updateSileoColors() {
        if UIColor.isDarkModeEnabled {
            self.popupBar.systemBarStyle = .black
            self.popupBar.toolbar.barStyle = .black
        } else {
            self.popupBar.systemBarStyle = .default
            self.popupBar.toolbar.barStyle = .default
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.tabBar.itemPositioning = .centered
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.updatePopup()
        }
    }
}
