/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `AssetPersistenceManager` is the main class in this sample that demonstrates how to
 manage downloading HLS streams.  It includes APIs for starting and canceling downloads,
 deleting existing assets off the users device, and monitoring the download progress.
 */

import Foundation
import AVFoundation

class AssetPersistenceManager: NSObject {
    // MARK: Properties
    
    /// Singleton for AssetPersistenceManager.
    static let sharedManager = AssetPersistenceManager()
    
    /// Internal Bool used to track if the AssetPersistenceManager finished restoring its state.
    private var didRestorePersistenceManager = false
    
    /// The AVAssetDownloadURLSession to use for managing AVAssetDownloadTasks.
    fileprivate var assetDownloadURLSession: AVAssetDownloadURLSession!
    
    /// Internal map of AVAssetDownloadTask to its corresponding Asset.
    fileprivate var activeDownloadsMap = [AVAssetDownloadTask: Asset]()
    
    /// Internal map of AVAssetDownloadTask to its resoled AVMediaSelection
    fileprivate var mediaSelectionMap = [AVAssetDownloadTask: AVMediaSelection]()
    
    // MARK: Intialization
    
    override private init() {
        
        super.init()
        
        // Create the configuration for the AVAssetDownloadURLSession.
        let backgroundConfiguration = URLSessionConfiguration.background(withIdentifier: "AAPL-Identifier")
        
        // Create the AVAssetDownloadURLSession using the configuration.
        assetDownloadURLSession =
            AVAssetDownloadURLSession(configuration: backgroundConfiguration,
                                      assetDownloadDelegate: self, delegateQueue: OperationQueue.main)
    }
    
    /// Restores the Application state by getting all the AVAssetDownloadTasks and restoring their Asset structs.
    func restorePersistenceManager() {
        guard !didRestorePersistenceManager else { return }
        
        didRestorePersistenceManager = true
        
        // Grab all the tasks associated with the assetDownloadURLSession
        assetDownloadURLSession.getAllTasks { tasksArray in
            // For each task, restore the state in the app by recreating Asset structs and reusing existing AVURLAsset objects.
            for task in tasksArray {
                guard let assetDownloadTask = task as? AVAssetDownloadTask, let assetName = task.taskDescription else { break }
                
                let stream = StreamListManager.shared.stream(withName: assetName)
                
                let urlAsset = assetDownloadTask.urlAsset
                
                let asset = Asset(stream: stream, urlAsset: urlAsset)
                
                self.activeDownloadsMap[assetDownloadTask] = asset
            }
            
            NotificationCenter.default.post(name: .AssetPersistenceManagerDidRestoreState, object: nil)
        }
    }
    
    /// Triggers the initial AVAssetDownloadTask for a given Asset.
    func downloadStream(for asset: Asset) {
        
        // Get the default media selections for the asset's media selection groups.
        let preferredMediaSelection = asset.urlAsset.preferredMediaSelection
        
        /*
         Creates and initializes an AVAggregateAssetDownloadTask to download multiple AVMediaSelections
         on an AVURLAsset.
         
         For the initial download, we ask the URLSession for an AVAssetDownloadTask with a minimum bitrate
         corresponding with one of the lower bitrate variants in the asset.
         */
        guard let task =
            assetDownloadURLSession.makeAssetDownloadTask(asset: asset.urlAsset,
                                assetTitle: asset.stream.name,
                                assetArtworkData: nil,
                                options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 265_000]) else { return }
        
        // To better track the AVAssetDownloadTask we set the taskDescription to something unique for our sample.
        task.taskDescription = asset.stream.name
        
        activeDownloadsMap[task] = asset
        
        task.resume()
        
        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = asset.stream.name
        userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloading.rawValue
        userInfo[Asset.Keys.downloadSelectionDisplayName] = displayNamesForSelectedMediaOptions(preferredMediaSelection)
        
        NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo: userInfo)
    }
    
    /// Returns an Asset given a specific name if that Asset is associated with an active download.
    func assetForStream(withName name: String) -> Asset? {
        var asset: Asset?
        
        for (_, assetValue) in activeDownloadsMap where name == assetValue.stream.name {
            asset = assetValue
            break
        }
        
        return asset
    }
    
    /// Returns an Asset pointing to a file on disk if it exists.
    func localAssetForStream(withName name: String) -> Asset? {
        let userDefaults = UserDefaults.standard
        guard let localFileLocation = userDefaults.value(forKey: name) as? Data else { return nil }
        
        var asset: Asset?
        var bookmarkDataIsStale = false
        do {
            guard let url = try URL(resolvingBookmarkData: localFileLocation,
                                    bookmarkDataIsStale: &bookmarkDataIsStale) else {
                                        fatalError("Failed to create URL from bookmark!")
            }
            
            if bookmarkDataIsStale {
                fatalError("Bookmark data is stale!")
            }
            
            let urlAsset = AVURLAsset(url: url)
            let stream = StreamListManager.shared.stream(withName: name)
            
            asset = Asset(stream: stream, urlAsset: urlAsset)
            
            return asset
        } catch {
            fatalError("Failed to create URL from bookmark with error: \(error)")
        }
    }
    
    /// Returns the current download state for a given Asset.
    func downloadState(for asset: Asset) -> Asset.DownloadState {
        // Check if there is a file URL stored for this asset.
        if let localFileLocation = localAssetForStream(withName: asset.stream.name)?.urlAsset.url {
            // Check if the file exists on disk
            if FileManager.default.fileExists(atPath: localFileLocation.path) {
                return .downloaded
            }
        }
        
        // Check if there are any active downloads in flight.
        for (_, assetValue) in activeDownloadsMap where asset.stream.name == assetValue.stream.name {
            return .downloading
        }
        
        return .notDownloaded
    }
    
    /// Deletes an Asset on disk if possible.
    func deleteAsset(_ asset: Asset) {
        let userDefaults = UserDefaults.standard
        
        do {
            if let localFileLocation = localAssetForStream(withName: asset.stream.name)?.urlAsset.url {
                try FileManager.default.removeItem(at: localFileLocation)
                
                userDefaults.removeObject(forKey: asset.stream.name)
                
                var userInfo = [String: Any]()
                userInfo[Asset.Keys.name] = asset.stream.name
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.notDownloaded.rawValue
                
                NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil,
                                                userInfo: userInfo)
            }
        } catch {
            print("An error occured deleting the file: \(error)")
        }
    }
    
    /// Cancels an AVAssetDownloadTask given an Asset.
    func cancelDownload(for asset: Asset) {
        var task: AVAssetDownloadTask?
        
        for (taskKey, assetVal) in activeDownloadsMap where asset == assetVal {
            task = taskKey
            break
        }
        
        task?.cancel()
    }
    
    // MARK: Convenience
    
    /**
     This function demonstrates returns the next `AVMediaSelectionGroup` and
     `AVMediaSelectionOption` that should be downloaded if needed. This is done
     by querying an `AVURLAsset`'s `AVAssetCache` for its available `AVMediaSelection`
     and comparing it to the remote versions.
     */
    fileprivate func nextMediaSelection(_ asset: AVURLAsset) -> (mediaSelectionGroup: AVMediaSelectionGroup?,
        mediaSelectionOption: AVMediaSelectionOption?) {
        guard let assetCache = asset.assetCache else { return (nil, nil) }
        
        let mediaCharacteristics = [AVMediaCharacteristic.audible, AVMediaCharacteristic.legible]
        
        for mediaCharacteristic in mediaCharacteristics {
            if let mediaSelectionGroup = asset.mediaSelectionGroup(forMediaCharacteristic: mediaCharacteristic) {
                let savedOptions = assetCache.mediaSelectionOptions(in: mediaSelectionGroup)
                
                if savedOptions.count < mediaSelectionGroup.options.count {
                    // There are still media options left to download.
                    for option in mediaSelectionGroup.options {
                        if !savedOptions.contains(option) && option.mediaType != AVMediaType.closedCaption.rawValue {
                            // This option has not been download.
                            return (mediaSelectionGroup, option)
                        }
                    }
                }
            }
        }
        
        // At this point all media options have been downloaded.
        return (nil, nil)
    }
}

/// Return the display names for the media selection options that are currently selected in the specified group
func displayNamesForSelectedMediaOptions(_ mediaSelection: AVMediaSelection) -> String {
    
    var displayNames = ""
    
    guard let asset = mediaSelection.asset else {
        return displayNames
    }
    
    // Iterate over every media characteristic in the asset in which a media selection option is available.
    for mediaCharacteristic in asset.availableMediaCharacteristicsWithMediaSelectionOptions {
        /*
         Obtain the AVMediaSelectionGroup object that contains one or more options with the
         specified media characteristic, then get the media selection option that's currently
         selected in the specified group.
         */
        guard let mediaSelectionGroup =
            asset.mediaSelectionGroup(forMediaCharacteristic: mediaCharacteristic),
            let option = mediaSelection.selectedMediaOption(in: mediaSelectionGroup) else { continue }
        
        // Obtain the display string for the media selection option.
        if displayNames.isEmpty {
            displayNames += " " + option.displayName
        } else {
            displayNames += ", " + option.displayName
        }
    }
    
    return displayNames
}

/**
 Extend `AssetPersistenceManager` to conform to the `AVAssetDownloadDelegate` protocol.
 */
extension AssetPersistenceManager: AVAssetDownloadDelegate {
    
    /// Tells the delegate that the task finished transferring data.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let userDefaults = UserDefaults.standard
        
        /*
         This is the ideal place to begin downloading additional media selections
         once the asset itself has finished downloading.
         */
        guard let task = task as? AVAssetDownloadTask, let asset = activeDownloadsMap.removeValue(forKey: task) else { return }
        
        // Prepare the basic userInfo dictionary that will be posted as part of our notification.
        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = asset.stream.name
        
        if let error = error as NSError? {
            switch (error.domain, error.code) {
            case (NSURLErrorDomain, NSURLErrorCancelled):
                /*
                 This task was canceled, you should perform cleanup using the
                 URL saved from AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didFinishDownloadingTo:).
                 */
                guard let localFileLocation = localAssetForStream(withName: asset.stream.name)?.urlAsset.url else { return }
                
                do {
                    try FileManager.default.removeItem(at: localFileLocation)
                    
                    userDefaults.removeObject(forKey: asset.stream.name)
                } catch {
                    print("An error occured trying to delete the contents on disk for \(asset.stream.name): \(error)")
                }
                
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.notDownloaded.rawValue
                
            case (NSURLErrorDomain, NSURLErrorUnknown):
                fatalError("Downloading HLS streams is not supported in the simulator.")
                
            default:
                fatalError("An unexpected error occured \(error.domain)")
            }
        } else {
            let mediaSelectionPair = nextMediaSelection(task.urlAsset)
            
            if mediaSelectionPair.mediaSelectionGroup != nil {
                /*
                 This task did complete sucessfully. At this point the application
                 can download additional media selections if needed.
                 
                 To download additional `AVMediaSelection`s, you should use the
                 `AVMediaSelection` reference saved in `AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didResolve:)`.
                 */
                
                guard let originalMediaSelection = mediaSelectionMap[task] else { return }
                
                /*
                 There are still media selections to download.
                 
                 Create a mutable copy of the AVMediaSelection reference saved in
                 `AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didResolve:)`.
                 */
                let mediaSelection = originalMediaSelection.mutableCopy() as! AVMutableMediaSelection
                
                // Select the AVMediaSelectionOption in the AVMediaSelectionGroup we found earlier.
                mediaSelection.select(mediaSelectionPair.mediaSelectionOption!,
                                      in: mediaSelectionPair.mediaSelectionGroup!)
                
                /*
                 Ask the `URLSession` to vend a new `AVAssetDownloadTask` using
                 the same `AVURLAsset` and assetTitle as before.
                 
                 This time, the application includes the specific `AVMediaSelection`
                 to download as well as a higher bitrate.
                 */
                guard let task = assetDownloadURLSession.makeAssetDownloadTask(asset: task.urlAsset,
                                                assetTitle: asset.stream.name,
                                                assetArtworkData: nil,
                                                options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 2_000_000,
                                                          AVAssetDownloadTaskMediaSelectionKey: mediaSelection])
                    else { return }
                
                task.taskDescription = asset.stream.name
                
                activeDownloadsMap[task] = asset
                
                task.resume()
                
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloading.rawValue
                userInfo[Asset.Keys.downloadSelectionDisplayName] = mediaSelectionPair.mediaSelectionOption!.displayName
                
                NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo: userInfo)
            } else {
                // All additional media selections have been downloaded.
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloaded.rawValue
                
            }
        }
        
        NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo: userInfo)
    }
    
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let userDefaults = UserDefaults.standard
        
        /*
         This delegate callback should only be used to save the location URL
         somewhere in your application. Any additional work should be done in
         `URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)`.
         */
        if let asset = activeDownloadsMap[assetDownloadTask] {
            
            do {
                let bookmark = try location.bookmarkData()
                
                userDefaults.set(bookmark, forKey: asset.stream.name)
            } catch {
                print("Failed to create bookmark for location: \(location)")
                deleteAsset(asset)
            }
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
                    totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        // This delegate callback should be used to provide download progress for your AVAssetDownloadTask.
        guard let asset = activeDownloadsMap[assetDownloadTask] else { return }
        
        var percentComplete = 0.0
        for value in loadedTimeRanges {
            let loadedTimeRange: CMTimeRange = value.timeRangeValue
            percentComplete +=
                CMTimeGetSeconds(loadedTimeRange.duration) / CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        }
        
        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = asset.stream.name
        userInfo[Asset.Keys.percentDownloaded] = percentComplete
        
        NotificationCenter.default.post(name: .AssetDownloadProgress, object: nil, userInfo: userInfo)
    }
    
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didResolve resolvedMediaSelection: AVMediaSelection) {
        /*
         You should be sure to use this delegate callback to keep a reference
         to `resolvedMediaSelection` so that in the future you can use it to
         download additional media selections.
         */
        mediaSelectionMap[assetDownloadTask] = resolvedMediaSelection
    }
}

extension Notification.Name {
    /// Notification for when download progress has changed.
    static let AssetDownloadProgress = Notification.Name(rawValue: "AssetDownloadProgressNotification")
    
    /// Notification for when the download state of an Asset has changed.
    static let AssetDownloadStateChanged = Notification.Name(rawValue: "AssetDownloadStateChangedNotification")
    
    /// Notification for when AssetPersistenceManager has completely restored its state.
    static let AssetPersistenceManagerDidRestoreState =
        Notification.Name(rawValue: "AssetPersistenceManagerDidRestoreStateNotification")
}
