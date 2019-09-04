/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The `ContentKeyManager` class configures the instance of `AssetResourceLoaderDelegate` to use for requesting
 content keys securely for playback or offline use.
 */

import AVFoundation

class ContentKeyManager {
    
    // MARK: Types.
    
    /// The singleton for `ContentKeyManager`.
    static let shared: ContentKeyManager = ContentKeyManager()
    
    // MARK: Properties.
    
    /**
     The instance of `AssetResourceLoaderDelegate` which conforms to `AVAssetResourceLoaderDelegate` and is used to respond to content key requests
     from `AVAssetResourceLoader`.
    */
    let assetResourceLoaderDelegate: AssetResourceLoaderDelegate

    /// The DispatchQueue to use for delegate callbacks.
    let assetResourceLoaderDelegateQueue = DispatchQueue(label: "com.example.apple-samplecode.HLSCatalog.AssetResourceLoaderDelegateQueue")
    
    // MARK: Initialization.
    
    private init() {
        assetResourceLoaderDelegate = AssetResourceLoaderDelegate()
    }
    
    func updateResourceLoaderDelegate(forAsset asset: AVURLAsset) {
        asset.resourceLoader.setDelegate(assetResourceLoaderDelegate, queue: assetResourceLoaderDelegateQueue)
    }
}
