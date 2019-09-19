/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `ContentKeyDelegate` is a class that implements the `AVContentKeySessionDelegate` protocol to respond to content key
 requests using FairPlay Streaming.
 */

import AVFoundation

class ContentKeyDelegate: NSObject, AVContentKeySessionDelegate {
    
    let releasePid: String = "mCFyF4sxoYjx"

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
    
    var dataTask: URLSessionDataTask!
    func requestApplicationCertificate(completionHandler: @escaping (Data?) -> Void) -> Void {
        
        // MARK: ADAPT - You must implement this method to retrieve your FPS application certificate.
        let session = URLSession.shared
        dataTask = session.dataTask(with: URL(string: "https://d1ee736ymvp3ne.cloudfront.net/fairplay.der")!)
        { (data, response, error) in
            guard error == nil else {
                return completionHandler(nil)
            }
            
            completionHandler(data)
        }
        
        dataTask.resume()
        
    }
    
    func requestContentKeyFromKeySecurityModule(spcData: Data, assetID: String, completionHandler: @escaping (Data?) -> Void) throws {
            
            // MARK: ADAPT - You must implement this method to request a CKC from your KSM.
            let session = URLSession(configuration: .default)
                
            var postRequest = URLRequest(url: URL(string: "https://fairplay.entitlement.theplatform.com/fpls/web/FairPlay?form=json&schema=1.0&token=Aj8XvsF6AOi-lOsYptuA4QBYMKBG8FAY&account=http://access.auth.theplatform.com/data/Account/2682481919")!)
            postRequest.httpMethod = "POST"
            postRequest.addValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            postRequest.httpBody = String(format: "{\"getFairplayLicense\": {\"spcMessage\": \"%@\",\"releasePid\": \"%@\"}}", spcData.base64EncodedString(), releasePid as CVarArg).data(using: .utf8)
            
            
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

    /// Preloads all the content keys associated with an Asset for persisting on disk.
    ///
    /// It is recommended you use AVContentKeySession to initiate the key loading process
    /// for online keys too. Key loading time can be a significant portion of your playback
    /// startup time because applications normally load keys when they receive an on-demand
    /// key request. You can improve the playback startup experience for your users if you
    /// load keys even before the user has picked something to play. AVContentKeySession allows
    /// you to initiate a key loading process and then use the key request you get to load the
    /// keys independent of the playback session. This is called key preloading. After loading
    /// the keys you can request playback, so during playback you don't have to load any keys,
    /// and the playback decryption can start immediately.
    ///
    /// In this sample use the Streams.plist to specify your own content key identifiers to use
    /// for loading content keys for your media. See the README document for more information.
    ///
    /// - Parameter asset: The `Asset` to preload keys for.
    func requestPersistableContentKeys(forAsset asset: Asset) {
        for identifier in asset.stream.contentKeyIDList ?? [] {
            
            guard let contentKeyIdentifierURL = URL(string: identifier), let assetIDString = contentKeyIdentifierURL.host else { continue }
            
            pendingPersistableContentKeyIdentifiers.insert(assetIDString)
            contentKeyToStreamNameMap[assetIDString] = asset.stream.name
            
            ContentKeyManager.shared.contentKeySession.processContentKeyRequest(withIdentifier: identifier, initializationData: nil, options: nil)
        }
    }
    
    /// Returns whether or not a content key should be persistable on disk.
    ///
    /// - Parameter identifier: The asset ID associated with the content key request.
    /// - Returns: `true` if the content key request should be persistable, `false` otherwise.
    func shouldRequestPersistableContentKey(withIdentifier identifier: String) -> Bool {
        return pendingPersistableContentKeyIdentifiers.contains(identifier)
    }
    
    // MARK: AVContentKeySessionDelegate Methods
    
    /*
     The following delegate callback gets called when the client initiates a key request or AVFoundation
     determines that the content is encrypted based on the playlist the client provided when it requests playback.
     */
    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        handleStreamingContentKeyRequest(keyRequest: keyRequest)
    }
    
    /*
     Provides the receiver with a new content key request representing a renewal of an existing content key.
     Will be invoked by an AVContentKeySession as the result of a call to -renewExpiringResponseDataForContentKeyRequest:.
     */
    func contentKeySession(_ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        handleStreamingContentKeyRequest(keyRequest: keyRequest)
    }
    
    /*
     Provides the receiver a content key request that should be retried because a previous content key request failed.
     Will be invoked by an AVContentKeySession when a content key request should be retried. The reason for failure of
     previous content key request is specified. The receiver can decide if it wants to request AVContentKeySession to
     retry this key request based on the reason. If the receiver returns YES, AVContentKeySession would restart the
     key request process. If the receiver returns NO or if it does not implement this delegate method, the content key
     request would fail and AVContentKeySession would let the receiver know through
     -contentKeySession:contentKeyRequest:didFailWithError:.
     */
    func contentKeySession(_ session: AVContentKeySession, shouldRetry keyRequest: AVContentKeyRequest,
                           reason retryReason: AVContentKeyRequestRetryReason) -> Bool {
        
        var shouldRetry = false
        
        switch retryReason {
            /*
             Indicates that the content key request should be retried because the key response was not set soon enough either
             due the initial request/response was taking too long, or a lease was expiring in the meantime.
             */
        case AVContentKeyRequestRetryReason.timedOut:
            shouldRetry = true
            
            /*
             Indicates that the content key request should be retried because a key response with expired lease was set on the
             previous content key request.
             */
        case AVContentKeyRequestRetryReason.receivedResponseWithExpiredLease:
            shouldRetry = true
            
            /*
             Indicates that the content key request should be retried because an obsolete key response was set on the previous
             content key request.
             */
        case AVContentKeyRequestRetryReason.receivedObsoleteContentKey:
            shouldRetry = true
            
        default:
            break
        }
        
        return shouldRetry
    }
    
    // Informs the receiver a content key request has failed.
    func contentKeySession(_ session: AVContentKeySession, contentKeyRequest keyRequest: AVContentKeyRequest, didFailWithError err: Error) {
        // Add your code here to handle errors.
    }
    
    // MARK: API
    
    func handleStreamingContentKeyRequest(keyRequest: AVContentKeyRequest) {
        let assetIDString = releasePid
        let assetIDData = assetIDString.data(using: .utf8)

//        guard let contentKeyIdentifierString = keyRequest.identifier as? String,
//            let contentKeyIdentifierURL = URL(string: contentKeyIdentifierString),
//            let assetIDString = contentKeyIdentifierURL.host,
//            let assetIDData = assetIDString.data(using: .utf8)
//            else {
//                print("Failed to retrieve the assetID from the keyRequest!")
//                return
//        }
//        print("+++", keyRequest.identifier!)

        let provideOnlinekey: () -> Void = { () -> Void in
            self.requestApplicationCertificate(completionHandler: { applicationCertificate in

                let completionHandler = { [weak self] (spcData: Data?, error: Error?) in
                    guard let strongSelf = self else { return }
                    if let error = error {
                        keyRequest.processContentKeyResponseError(error)
                        return
                    }

                    guard let spcData = spcData else { return }

                    do{
                        // Send SPC to Key Server and obtain CKC
                        try strongSelf.requestContentKeyFromKeySecurityModule(spcData: spcData, assetID: strongSelf.releasePid, completionHandler: { ckcData in
                            /*
                            AVContentKeyResponse is used to represent the data returned from the key server when requesting a key for
                            decrypting content.
                            */
                           let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckcData!)

                           /*
                            Provide the content key response to make protected content available for processing.
                            */
                           keyRequest.processContentKeyResponse(keyResponse)

                            
                        })
                    } catch {
                        keyRequest.processContentKeyResponseError(error)
                    }
                }

                keyRequest.makeStreamingContentKeyRequestData(forApp: applicationCertificate!,
                                                              contentIdentifier: assetIDData!,
                                                              options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                              completionHandler: completionHandler)
            })
        }

        #if os(iOS)
            /*
             When you receive an AVContentKeyRequest via -contentKeySession:didProvideContentKeyRequest:
             and you want the resulting key response to produce a key that can persist across multiple
             playback sessions, you must invoke -respondByRequestingPersistableContentKeyRequest on that
             AVContentKeyRequest in order to signal that you want to process an AVPersistableContentKeyRequest
             instead. If the underlying protocol supports persistable content keys, in response your
             delegate will receive an AVPersistableContentKeyRequest via -contentKeySession:didProvidePersistableContentKeyRequest:.
             */
            if shouldRequestPersistableContentKey(withIdentifier: assetIDString) ||
                persistableContentKeyExistsOnDisk(withContentKeyIdentifier: assetIDString) {

//                 Request a Persistable Key Request.
                if #available(iOS 11.2, *) {
                    do {
                        try keyRequest.respondByRequestingPersistableContentKeyRequestAndReturnError()
                    } catch {

                        /*
                        This case will occur when the client gets a key loading request from an AirPlay Session.
                        You should answer the key request using an online key from your key server.
                        */
                        provideOnlinekey()
                    }
                } else {
                    keyRequest.respondByRequestingPersistableContentKeyRequest()
                }

                return
            }
        #endif
        
        provideOnlinekey()
    }
}
