//
//  AltIconTableViewController.swift
//  Sileo
//
//  Created by Amy on 21/03/2021.
//  Copyright © 2021 CoolStar. All rights reserved.
//

import UIKit

struct AltIcon {
    var displayName: String
    var author: String
    var key: String?
    var image: UIImage
}

class AltIconTableViewController: UITableViewController {
    
    private class func altImage(_ name: String) -> UIImage {
        let path = Bundle.main.bundleURL.appendingPathComponent(name + "@2x.png")
        return UIImage(contentsOfFile: path.path) ?? UIImage()
    }
    
    let icons = [
        AltIcon(displayName: "Stock", author: "Dennis Bednarz", key: nil, image: altImage("AppIcon60x60")),
        AltIcon(displayName: "OG", author: "Dennis Bednarz", key: "OG", image: altImage("OG")),
        AltIcon(displayName: "Taurine", author: "Alpha_Stream", key: "Taurine", image: altImage("Taurine")),
        AltIcon(displayName: "Chimera", author: "Korfi", key: "Chimera", image: altImage("Chimera")),
        AltIcon(displayName: "Procursus", author: "Korfi", key: "Procursus", image: altImage("Procursus")),
        AltIcon(displayName: "Sugar Free", author: "Alpha_Stream", key: "SugarFree", image: altImage("SugarFree")),
        AltIcon(displayName: "Mango Crazy", author: "Alpha_Stream", key: "MangoCrazy", image: altImage("MangoCrazy")),
        AltIcon(displayName: "Cool Breeze", author: "Alpha_Stream", key: "CoolBreeze", image: altImage("CoolBreeze")),
        AltIcon(displayName: "Blue Lemonade", author: "Alpha_Stream ", key: "BlueLemonade", image: altImage("BlueLemonade")),
        AltIcon(displayName: "Cotton Candy", author: "emiyl0", key: "CottonCandy", image: altImage("CottonCandy")),
        AltIcon(displayName: "Strawberry Sunset", author: "Korfi", key: "StrawberrySunset", image: altImage("StrawberrySunset")),
        AltIcon(displayName: "Oceanic Blue", author: "Korfi", key: "OceanicBlue", image: altImage("OceanicBlue")),
        AltIcon(displayName: "Sus", author: "emiyl0", key: "Sus", image: altImage("Sus"))
    ]
    
    @objc func updateSileoColors() {
        self.tableView.separatorColor = .sileoSeparatorColor
        self.tableView.backgroundColor = .sileoBackgroundColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = String(localizationKey: "Alternate_Icon_Title")
        self.tableView.separatorColor = .sileoSeparatorColor
        self.tableView.backgroundColor = .sileoBackgroundColor
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.tableFooterView = UIView()
        self.tableView.rowHeight = 75
                
        weak var weakSelf = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        icons.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = AltIconTableViewCell()
        cell.altIcon = icons[indexPath.row]
        if UIApplication.shared.alternateIconName == cell.altIcon?.key {
            cell.accessoryType = .checkmark
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let altIcon = icons[indexPath.row]
        UIApplication.shared.setAlternateIconName(altIcon.key) { _ in }
        self.tableView.reloadRows(at: self.tableView.indexPathsForVisibleRows ?? [IndexPath](), with: .none)
    }

}
