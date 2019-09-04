/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 This extension on `AssetResourceLoaderDelegate` implements the methods related to persistable content keys.
 */

import AVFoundation

extension AssetResourceLoaderDelegate {
    
    func prepareAndSendPersistableContentKeyRequest(resourceLoadingRequest: AVAssetResourceLoadingRequest) {
        
        /*
         The key ID is the URI from the EXT-X-KEY tag in the playlist (e.g. "skd://key65") and the
         asset ID in this case is "key65".
         */
        guard let contentKeyIdentifierURL = resourceLoadingRequest.request.url,
            let assetIDString = contentKeyIdentifierURL.host,
            let assetIDData = assetIDString.data(using: .utf8) else {
                print("Failed to get url or assetIDString for the request object of the resource.")
                return
        }
        
        resourceLoadingRequest.contentInformationRequest?.contentType = AVStreamingKeyDeliveryPersistentContentKeyType
        
        do {
            
            // Check to see if we can satisfy this key request using a saved persistent key file.
            if persistableContentKeyExistsOnDisk(withContentKeyIdentifier: assetIDString) {
                let urlToPersistableKey = urlForPersistableContentKey(withContentKeyIdentifier: assetIDString)
                
                guard let contentKey = FileManager.default.contents(atPath: urlToPersistableKey.path) else {
                    // Error Handling.
                    
                    pendingPersistableContentKeyIdentifiers.remove(assetIDString)
                    return
                }
                
                // Provide the content key response to make protected content available for processing.
                resourceLoadingRequest.dataRequest?.respond(with: contentKey)
                resourceLoadingRequest.finishLoading()
                
                return
            }
            
            requestApplicationCertificate(completionHandler: { applicationCertificate in
                do {
                    let spcData =
                        try resourceLoadingRequest.streamingContentKeyRequestData(forApp: applicationCertificate!,
                                                                                  contentIdentifier: assetIDData,
                                                                                  options: [AVAssetResourceLoadingRequestStreamingContentKeyRequestRequiresPersistentKey: true])
                    
                    // Send SPC to Key Server and obtain CKC
                    try self.requestContentKeyFromKeySecurityModule(spcData: spcData, assetID: assetIDString, completionHandler: { ckcData in
                        
                        do {
                            let persistentKey = try resourceLoadingRequest.persistentContentKey(fromKeyVendorResponse: ckcData!, options: nil)
                            
                            // Write the persistent content key to disk.
                            try self.writePersistableContentKey(contentKey: persistentKey, withContentKeyIdentifier: assetIDString)
                            
                            // Provide the content key response to make protected content available for processing.
                            resourceLoadingRequest.dataRequest?.respond(with: persistentKey)
                            resourceLoadingRequest.finishLoading()
                            
                            let assetName = self.contentKeyToStreamNameMap.removeValue(forKey: assetIDString)!
                            
                            if !self.contentKeyToStreamNameMap.values.contains(assetName) {
                                NotificationCenter.default.post(name: .DidSaveAllPersistableContentKey,
                                                                object: nil,
                                                                userInfo: ["name": assetName])
                            }
                            
                            self.pendingPersistableContentKeyIdentifiers.remove(assetIDString)
                        } catch {
                            resourceLoadingRequest.finishLoading(with: error)
                            
                            self.pendingPersistableContentKeyIdentifiers.remove(assetIDString)
                        }
                        
                    })
                    
                    

                } catch {
                    resourceLoadingRequest.finishLoading(with: error)
                    
                    self.pendingPersistableContentKeyIdentifiers.remove(assetIDString)
                }
            })
        } catch {
            resourceLoadingRequest.finishLoading(with: error)
            
            pendingPersistableContentKeyIdentifiers.remove(assetIDString)
        }
    }
    
    /// Deletes all the persistable content keys on disk for a specific `Asset`.
    ///
    /// - Parameter asset: The `Asset` value to remove keys for.
    func deleteAllPeristableContentKeys(forAsset asset: Asset) {
        for contentKeyIdentifier in asset.stream.contentKeyIDList ?? [] {
            deletePeristableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        }
    }
    
    /// Deletes a persistable key for a given content key identifier.
    ///
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    func deletePeristableContentKey(withContentKeyIdentifier contentKeyIdentifier: String) {
        
        guard persistableContentKeyExistsOnDisk(withContentKeyIdentifier: contentKeyIdentifier) else { return }
        
        let contentKeyURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        do {
            try FileManager.default.removeItem(at: contentKeyURL)
            
            UserDefaults.standard.removeObject(forKey: "\(contentKeyIdentifier)-Key")
        } catch {
            print("An error occured removing the persisted content key: \(error)")
        }
    }
    
    /// Returns whether or not a persistable content key exists on disk for a given content key identifier.
    ///
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    /// - Returns: `true` if the key exists on disk, `false` otherwise.
    func persistableContentKeyExistsOnDisk(withContentKeyIdentifier contentKeyIdentifier: String) -> Bool {
        let contentKeyURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        return FileManager.default.fileExists(atPath: contentKeyURL.path)
    }
    
    // MARK: Private APIs
    
    /// Returns the `URL` for persisting or retrieving a persistable content key.
    ///
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    /// - Returns: The fully resolved file URL.
    func urlForPersistableContentKey(withContentKeyIdentifier contentKeyIdentifier: String) -> URL {
        return contentKeyDirectory.appendingPathComponent("\(contentKeyIdentifier)-Key")
    }
    
    /// Writes out a persistable content key to disk.
    ///
    /// - Parameters:
    ///   - contentKey: The data representation of the persistable content key.
    ///   - contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    /// - Throws: If an error occurs during the file write process.
    func writePersistableContentKey(contentKey: Data, withContentKeyIdentifier contentKeyIdentifier: String) throws {
        
        let fileURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        try contentKey.write(to: fileURL, options: Data.WritingOptions.atomicWrite)
    }

}

extension Notification.Name {
    
    /**
     The notification that is posted when all the content keys for a given asset have been saved to disk.
     */
    static let DidSaveAllPersistableContentKey =
        Notification.Name("AssetResourceLoaderDelegateDidSaveAllPersistableContentKey")
}

