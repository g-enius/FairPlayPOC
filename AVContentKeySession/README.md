# HLS Catalog with FPS: Using AVFoundation to play and persist HTTP Live Streams with FairPlay Streaming Content Protection

This sample demonstrates how to use the AVFoundation framework to play HTTP Live Streams hosted on remote servers as well as how to persist the HLS streams on disk for offline playback.

To learn more about FairPlay Streaming, see the FairPlay Streaming Programming Guide which is part of the "FPS Server SDK" package.  The latest version of this package can be found at <https://developer.apple.com/streaming/fps>.

## Using the Sample

Build and run the sample on an actual device running iOS 11.0 or later using Xcode.  The APIs demonstrated in this sample do not work on the iOS Simulator.

This sample provides a list of HLS Streams that you can playback by tapping on the UITableViewCell corresponding to the stream.  If you wish to manage the download of an HLS stream such as initiating an `AVAggregateAssetDownloadTask`, canceling an already running `AVAggregateAssetDownloadTask` or deleteting an already downloaded HLS stream from disk, you can accomplish this by tapping on the accessory button on the `UITableViewCell` corresponding to the stream you wish to manage.

When the sample creates and initializes an `AVAggregateAssetDownloadTask` for the download of an HLS stream, only the default selections for each of the media selection groups will be used (these are indicated in the HLS playlist `EXT-X-MEDIA` tags by a DEFAULT attribute of YES).

### Adding Streams to the Sample

If you wish to add your own HLS streams to test with using this sample, you can do this by adding an entry into the Streams.plist that is part of the Xcode Project.  There are two important keys you need to provide values for:

__name__: What the display name of the HLS stream should be in the sample.

__playlist_url__: The URL of the HLS stream's master playlist.

__is_protected__: Whether or not the stream is protected using FPS.

__content\_key\_id\_list__: An array of content key identifiers to use for loading content keys for content using FPS.  The values are strings in the form of the URIs used in the X-EXT-KEY tag for loading content keys.  For example: "skd://twelve"

### Application Transport Security

If any of the streams you add are not hosted securely, you will need to add an Application Transport Security (ATS) exception in the Info.plist.  More information on ATS and the relevant plist keys can be found in the following article:

Information Property List Key Reference - NSAppTransportSecurity: <https://developer.apple.com/library/ios/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW33>

## Important Notes

Saving HLS streams for offline playback is only supported for VOD streams.  If you try to save a live HLS stream, the system will throw an exception. 

## Main Files

__AssetPersistenveManager.swift__: 

- `AssetPersistenceManager` is the main class in this sample that demonstrates how to manage downloading HLS streams.  It includes APIs for starting and canceling downloads, deleting existing assets off the users device, and monitoring the download progress.

__AssetPlaybackManager.swift__:

- `AssetPlaybackManager` is the class that manages the playback of Assets in this sample using Key-value observing on various AVFoundation classes.

__AssetListManager.swift__:

- The `AssetListManager` class is responsible for providing a list of assets to present in the `AssetListTableViewController`.

__StreamListManager.swift__:

- The `StreamListManager` class manages loading reading the contents of the `Streams.plist` file in the application bundle.

__ContentKeyManager.swift__:

- The `ContentKeyManager` class configures the instance of `AVContentKeySession` to use for requesting content keys securely for playback or offline use.

__ContentKeyLoader.swfit__:

- `ContentKeyDelegate` is a class that implements the `AVContentKeySessionDelegate` protocol to respond to content key requests using FairPlay Streaming.

__ContentKeyDelegate+Persistable.swift__:

- This extension on `ContentKeyDelegate` implements the `AVContentKeySessionDelegate` protocol methods related to persistable content keys.

## Helpful Resources

The following resources available on the Apple Developer website contain helpful information that you may find useful

* General information regarding HLS on supported Apple devices and platforms:
    * [HTTP Live Streaming (HLS) - Apple Developer](https://developer.apple.com/streaming/)
    * [AV Foundation - Apple Developer](https://developer.apple.com/av-foundation/)
* For information regarding topics specific to FairPlay Streaming as well as the latest version of the FairPlay Streaming Server SDK, please see:
    * [FairPlay Streaming - Apple Developer](http://developer.apple.com/streaming/fps/).
* Information regarding authoring HLS content for devices and platforms:
    * [HLS Authoring Specification for Apple Devices](https://developer.apple.com/library/content/documentation/General/Reference/HLSAuthoringSpec/index.html#//apple_ref/doc/uid/TP40016596-CH4-SW1)
    * [WWDC 2016 - Session 510: Validating HTTP Live Streams](https://developer.apple.com/videos/play/wwdc2016/510/)
    * [WWDC 2017 - Session 515: HLS Authoring Update](https://developer.apple.com/videos/play/wwdc2017/515/)
* Information regarding error handling on the server side and with AVFoundation on supported Apple devices and platforms:
    * [WWDC 2017 - Session 514: Error Handling Best Practices for HTTP Live Streaming](https://developer.apple.com/videos/play/wwdc2017/514/)

## Requirements

### Build

Xcode 9.0 or later; iOS 11.0 SDK or later

### Runtime

iOS 11.0 or later.

Copyright (C) 2017-2018 Apple Inc. All rights reserved.
