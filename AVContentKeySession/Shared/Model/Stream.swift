/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 A simple class that represents an entry from the `Streams.plist` file in the main application bundle.
 */

import Foundation

class Stream: Codable {
    
    // MARK: Types
    
    enum CodingKeys: String, CodingKey {
        case name = "name"
        case playlistURL = "playlist_url"
        case isProtected = "is_protected"
        case contentKeyIDList = "content_key_id_list"
    }
    
    // MARK: Properties
    
    /// The name of the stream.
    let name: String
    
    /// The URL pointing to the HLS stream.
    let playlistURL: String
    
    /// A Boolen value representing if the stream uses FPS.
    let isProtected: Bool
    
    /// An array of content IDs to use for loading content keys with FPS.
    let contentKeyIDList: [String]?
}

extension Stream: Equatable {
    static func ==(lhs: Stream, rhs: Stream) -> Bool {
        var isEqual = (lhs.name == rhs.name) && (lhs.playlistURL == rhs.playlistURL) && (lhs.isProtected == rhs.isProtected)
        
        let lhsContentKeyIDList = lhs.contentKeyIDList ?? []
        let rhsContentKeyIDList = rhs.contentKeyIDList ?? []
        
        isEqual = isEqual && lhsContentKeyIDList.elementsEqual(rhsContentKeyIDList)
        
        return isEqual
    }
}
