/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `AssetResourceLoaderDelegate` is a class that implements the `AVAssetResourceLoaderDelegate` protocol to respond
 to content key requests using FairPlay Streaming.
 */

import AVFoundation

class AssetResourceLoaderDelegate: NSObject {
    
    // MARK: Types
    
    enum ProgramError: Error {
        case missingApplicationCertificate
        case noCKCReturnedByKSM
    }
    
    // MARK: Properties
    
    /// The directory that is used to save persistable content keys.
    lazy var contentKeyDirectory: URL = {
        guard let documentPath =
            NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
                fatalError("Unable to determine library URL")
        }
        
        let documentURL = URL(fileURLWithPath: documentPath)
        
        let contentKeyDirectory = documentURL.appendingPathComponent(".keys", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: contentKeyDirectory.path, isDirectory: nil) {
            do {
                try FileManager.default.createDirectory(at: contentKeyDirectory,
                                                        withIntermediateDirectories: false,
                                                        attributes: nil)
            } catch {
                fatalError("Unable to create directory for content keys at path: \(contentKeyDirectory.path)")
            }
        }
        
        return contentKeyDirectory
    }()
    
    /// A set containing the currently pending content key identifiers associated with persistable content key requests that have not been completed.
    var pendingPersistableContentKeyIdentifiers = Set<String>()
    
    /// A dictionary mapping content key identifiers to their associated stream name.
    var contentKeyToStreamNameMap = [String: String]()
    
    /// The DispatchQueue to use for AVAssetResourceLoaderDelegate callbacks.
    fileprivate let resourceLoadingRequestQueue = DispatchQueue(label: "com.example.apple-samplecode.resourcerequests")
    
    // MARK: API
    
    /// Preloads all the content keys associated with an Asset for persisting on disk.
    ///
    /// - Parameter asset: The `Asset` to preload keys for.
    func requestPersistableContentKeys(forAsset asset: Asset) {
        for identifier in asset.stream.contentKeyIDList ?? [] {
            
            guard let contentKeyIdentifierURL = URL(string: identifier), let assetIDString = contentKeyIdentifierURL.host else { continue }
            
            pendingPersistableContentKeyIdentifiers.insert(assetIDString)
            contentKeyToStreamNameMap[assetIDString] = asset.stream.name
            
            asset.urlAsset.resourceLoader.preloadsEligibleContentKeys = true
        }
    }
    
    /// Returns whether or not a content key should be persistable on disk.
    ///
    /// - Parameter identifier: The asset ID associated with the content key request.
    /// - Returns: `true` if the content key request should be persistable, `false` otherwise.
    func shouldRequestPersistableContentKey(withIdentifier identifier: String) -> Bool {
        return pendingPersistableContentKeyIdentifiers.contains(identifier)
    }
    
    var dataTask: URLSessionDataTask!
    func requestApplicationCertificate(completionHandler: @escaping (Data?) -> Void){
        
        // MARK: ADAPT - You must implement this method to retrieve your FPS application certificate.
        
        let session = URLSession(configuration: .default)
        dataTask = session.dataTask(with: URL(string: "https://d1ee736ymvp3ne.cloudfront.net/fairplay.der")!) { (data, response, error) in
            completionHandler(data)
        }
        
        dataTask.resume()
        
//        guard applicationCertificate != nil else {
//            throw ProgramError.missingApplicationCertificate
//        }
        
    }
    
    func requestContentKeyFromKeySecurityModule(spcData: Data, assetID: String, completionHandler: @escaping (Data?) -> Void) throws {
        
        // MARK: ADAPT - You must implement this method to request a CKC from your KSM.
        let session = URLSession(configuration: .default)
            
        var postRequest = URLRequest(url: URL(string: "https://fairplay.entitlement.theplatform.com/fpls/web/FairPlay?form=json&schema=1.0&token=EK4p9zhkuQMEC0aWJisUkVB-wCAukLAa&account=http://access.auth.theplatform.com/data/Account/2682481919")!)
        postRequest.httpMethod = "POST"
        postRequest.addValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        postRequest.httpBody = String(format: "{\"getFairplayLicense\": {\"spcMessage\": \"%@\",\"releasePid\": \"pFuwybxW35Ak\"}}", spcData.base64EncodedString() as CVarArg).data(using: .utf8)
        
        
        dataTask = session.dataTask(with: postRequest) { (data, response, error) in
            do {
                let json = try JSONDecoder().decode([String: Dictionary<String, String>].self, from: data!)
                let ckc = json["getFairplayLicenseResponse"]!["ckcResponse"]!
                let ckcData = Data(base64Encoded: ckc)
                completionHandler(ckcData)

            } catch {
                
            }
            
        }
        
        dataTask.resume()
//        let ckcData: Data? = nil
//
//        guard ckcData != nil else {
//            throw ProgramError.noCKCReturnedByKSM
//        }
//
//        return ckcData!
    }
    
    func shouldLoadOrRenewRequestedResource(resourceLoadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        
        guard let url = resourceLoadingRequest.request.url else {
            return false
        }
        
        // AssetLoaderDelegate only should handle FPS Content Key requests.
        if url.scheme != "skd" {
            return false
        }
        
        resourceLoadingRequestQueue.async { [weak self] in
            self?.prepareAndSendContentKeyRequest(resourceLoadingRequest: resourceLoadingRequest)
        }
        
        return true
    }
    
    func prepareAndSendContentKeyRequest(resourceLoadingRequest: AVAssetResourceLoadingRequest) {
        
        let assetIDString = "pFuwybxW35Ak"
        guard let contentKeyIdentifierURL = resourceLoadingRequest.request.url,
            let assetIDData = assetIDString.data(using: .utf8) else {
                print("Failed to get url or assetIDString for the request object of the resource.")
                return
        }
        
        let provideOnlineKey: () -> Void = { () in
            do {
                self.requestApplicationCertificate(completionHandler: { applicationCertificate in
                    do {
                        let spcData = try resourceLoadingRequest.streamingContentKeyRequestData(forApp: applicationCertificate!,
                                                                                                contentIdentifier: assetIDData,
                                                                                                options: nil)
                        
                        // Send SPC to Key Server and obtain CKC.
                        let ckcData = try self.requestContentKeyFromKeySecurityModule(spcData: spcData, assetID: assetIDString, completionHandler: { ckcData in
                            do {
                                resourceLoadingRequest.dataRequest?.respond(with: ckcData!)
                                /*
                                 You should always set the contentType before calling finishLoading() to make sure you
                                 have a contentType that matches the key response.
                                 */
                                resourceLoadingRequest.contentInformationRequest?.contentType = AVStreamingKeyDeliveryContentKeyType
                                resourceLoadingRequest.finishLoading()
                            } catch {
                                resourceLoadingRequest.finishLoading(with: error)

                            }
                        })
                        
                       
                    } catch {
                        resourceLoadingRequest.finishLoading(with: error)
                    }
                })
            } catch {
                resourceLoadingRequest.finishLoading(with: error)
            }
        }
        
        #if os(iOS)
        /*
         Look up if this request should request a persistable content key or if there is an existing one to use on disk.
         */

        /*
        Make sure this key request supports persistent content keys before proceeding.
         
        Clients can respond with a persistent key if allowedContentTypes is nil or if allowedContentTypes
        contains AVStreamingKeyDeliveryPersistentContentKeyType. In all other cases, the client should
        respond with an online key.
        */
        if  let contentTypes = resourceLoadingRequest.contentInformationRequest?.allowedContentTypes,
            !contentTypes.contains(AVStreamingKeyDeliveryPersistentContentKeyType) {
            
            // Fallback to provide online FairPlay Streaming key from key server.
            provideOnlineKey()

            return
        }

        if shouldRequestPersistableContentKey(withIdentifier: assetIDString) ||
            persistableContentKeyExistsOnDisk(withContentKeyIdentifier: assetIDString) {
            
            prepareAndSendPersistableContentKeyRequest(resourceLoadingRequest: resourceLoadingRequest)
            
            return
        }
        #endif

        // Provide online FairPlay Streaming key from key server.
        provideOnlineKey()
    }
}

// MARK: - AVAssetResourceLoaderDelegate protocol methods extension
extension AssetResourceLoaderDelegate: AVAssetResourceLoaderDelegate {
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        print("\(#function) was called in AssetLoaderDelegate with loadingRequest: \(loadingRequest)")
        
        return shouldLoadOrRenewRequestedResource(resourceLoadingRequest: loadingRequest)
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        print("\(#function) was called in AssetLoaderDelegate with renewalRequest: \(renewalRequest)")
        
        return shouldLoadOrRenewRequestedResource(resourceLoadingRequest: renewalRequest)
    }
}
