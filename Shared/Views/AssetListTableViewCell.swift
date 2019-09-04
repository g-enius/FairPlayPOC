/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `AssetListTableViewCell` is the `UITableViewCell` subclass that represents an `Asset` visually in
 `AssetListTableViewController`.  This cell handles responding to user events as well as updating
 itself to reflect the state of the `Asset` if it has been downloaded, deleted, or is actively downloading.
 */

import UIKit

class AssetListTableViewCell: UITableViewCell {
    // MARK: Properties
    
    static let reuseIdentifier = "AssetListTableViewCellIdentifier"
    
    @IBOutlet weak var assetNameLabel: UILabel!
    
    #if os(iOS)
    @IBOutlet weak var downloadStateLabel: UILabel!
    
    @IBOutlet weak var downloadProgressView: UIProgressView!
    
    #endif
    
    weak var delegate: AssetListTableViewCellDelegate?
    
    var asset: Asset? {
        didSet {
            if let asset = asset {
                #if os(iOS)
                    let downloadState = AssetPersistenceManager.sharedManager.downloadState(for: asset)
                    
                    switch downloadState {
                    case .downloaded:
                        downloadProgressView.isHidden = true
                        
                    case .downloading:
                        
                        downloadProgressView.isHidden = false
                        
                    case .notDownloaded:
                        break
                    }
                    
                    downloadStateLabel.text = downloadState.rawValue
                    
                    let notificationCenter = NotificationCenter.default
                    notificationCenter.addObserver(self,
                                                   selector: #selector(handleAssetDownloadStateChanged(_:)),
                                                   name: .AssetDownloadStateChanged, object: nil)
                    notificationCenter.addObserver(self, selector: #selector(handleAssetDownloadProgress(_:)),
                                                   name: .AssetDownloadProgress, object: nil)
                #endif
                
                assetNameLabel.text = asset.stream.name
            } else {
                assetNameLabel.text = ""
                
                #if os(iOS)
                    downloadProgressView.isHidden = false
                    downloadStateLabel.text = ""
                #endif
            }
        }
    }
    
    // MARK: Notification handling
    #if os(iOS)
    @objc
    func handleAssetDownloadStateChanged(_ notification: Notification) {
        guard let assetStreamName = notification.userInfo![Asset.Keys.name] as? String,
            let downloadStateRawValue = notification.userInfo![Asset.Keys.downloadState] as? String,
            let downloadState = Asset.DownloadState(rawValue: downloadStateRawValue),
            let asset = asset,
            asset.stream.name == assetStreamName else { return }
        
        DispatchQueue.main.async {
            switch downloadState {
            case .downloading:
                self.downloadProgressView.isHidden = false
                
                if let downloadSelection = notification.userInfo?[Asset.Keys.downloadSelectionDisplayName] as? String {
                    self.downloadStateLabel.text = "\(downloadState): \(downloadSelection)"
                    return
                }
                
            case .downloaded, .notDownloaded:
                self.downloadProgressView.isHidden = true
            }
            
            self.delegate?.assetListTableViewCell(self, downloadStateDidChange: downloadState)
        }
    }
    
    @objc
    func handleAssetDownloadProgress(_ notification: Notification) {
        guard let assetStreamName = notification.userInfo![Asset.Keys.name] as? String, let asset = asset,
            asset.stream.name == assetStreamName else { return }
        guard let progress = notification.userInfo![Asset.Keys.percentDownloaded] as? Double else { return }

        self.downloadProgressView.setProgress(Float(progress), animated: true)
    }
    #endif
}

protocol AssetListTableViewCellDelegate: AnyObject {
    
    func assetListTableViewCell(_ cell: AssetListTableViewCell, downloadStateDidChange newState: Asset.DownloadState)
}
