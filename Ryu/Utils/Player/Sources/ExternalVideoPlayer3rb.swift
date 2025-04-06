//
//  ExternalVideoPlayer3rb.swift
//  Ryu
//
//  Created by Francesco on 08/07/24.
//

import AVKit
import WebKit
import SwiftSoup
import GoogleCast

class ExternalVideoPlayer3rb: UIViewController, GCKRemoteMediaClientListener {
    private let streamURL: String
    private var webView: WKWebView?
    private var player: AVPlayer?
    private var playerViewController: AVPlayerViewController?
    private var activityIndicator: UIActivityIndicatorView?
    
    private var progressView: UIProgressView?
    private var progressLabel: UILabel?
    
    private var retryCount = 0
    private let maxRetries: Int
    
    private var cell: EpisodeCell
    private var fullURL: String
    private weak var animeDetailsViewController: AnimeDetailViewController?
    private var timeObserverToken: Any?
    
    private var originalRate: Float = 1.0
    private var holdGesture: UILongPressGestureRecognizer?
    private var qualityOptions: [(label: String, url: URL)] = []
    
    init(streamURL: String, cell: EpisodeCell, fullURL: String, animeDetailsViewController: AnimeDetailViewController) {
        self.streamURL = streamURL
        self.cell = cell
        self.fullURL = fullURL
        self.animeDetailsViewController = animeDetailsViewController
        
        let userDefaultsRetries = UserDefaults.standard.integer(forKey: "maxRetries")
        self.maxRetries = userDefaultsRetries > 0 ? userDefaultsRetries : 10
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadInitialURL()
        setupHoldGesture()
        setupNotificationObserver()
    }
    
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd), name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UserDefaults.standard.set(false, forKey: "isToDownload")
        cleanup()
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UserDefaults.standard.bool(forKey: "AlwaysLandscape") {
            return .landscape
        } else {
            return .all
        }
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    override var childForHomeIndicatorAutoHidden: UIViewController? {
        return playerViewController
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return playerViewController
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.secondarySystemBackground
        setupActivityIndicator()
        setupWebView()
    }
    
    private func setupHoldGesture() {
        holdGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleHoldGesture(_:)))
        holdGesture?.minimumPressDuration = 0.5
        if let holdGesture = holdGesture {
            view.addGestureRecognizer(holdGesture)
        }
    }
    
    @objc private func handleHoldGesture(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginHoldSpeed()
        case .ended, .cancelled:
            endHoldSpeed()
        default:
            break
        }
    }
    
    private func beginHoldSpeed() {
        guard let player = player else { return }
        originalRate = player.rate
        let holdSpeed = UserDefaults.standard.float(forKey: "holdSpeedPlayer")
        player.rate = holdSpeed
    }
    
    private func endHoldSpeed() {
        player?.rate = originalRate
    }
    
    private func setupActivityIndicator() {
        activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator?.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator?.hidesWhenStopped = true
        
        if let activityIndicator = activityIndicator {
            view.addSubview(activityIndicator)
            
            NSLayoutConstraint.activate([
                activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            
            activityIndicator.startAnimating()
        }
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView?.navigationDelegate = self
    }
    
    private func loadInitialURL() {
        guard let url = URL(string: streamURL) else {
            print("Invalid stream URL")
            return
        }
        let request = URLRequest(url: url)
        webView?.load(request)
    }
    
    private func loadIframeContent(url: URL) {
        let request = URLRequest(url: url)
        webView?.load(request)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.extractVideoSource()
        }
    }
    
    private func extractIframeSource() {
        webView?.evaluateJavaScript("document.body.innerHTML") { [weak self] (result, error) in
            guard let self = self, let htmlString = result as? String else {
                print("Error getting HTML: \(error?.localizedDescription ?? "Unknown error")")
                self?.retryExtraction()
                return
            }
            
            if let iframeURL = self.extractIframeSourceURL(from: htmlString) {
                print("Iframe src URL found: \(iframeURL.absoluteString)")
                self.loadIframeContent(url: iframeURL)
            } else {
                print("No iframe source found")
                self.retryExtraction()
            }
        }
    }
    
    private func extractVideoSource() {
        webView?.evaluateJavaScript("document.body.innerHTML") { [weak self] (result, error) in
            guard let self = self, let htmlString = result as? String else {
                print("Error getting HTML: \(error?.localizedDescription ?? "Unknown error")")
                self?.retryExtraction()
                return
            }
            
            if let qualityOptions = self.extractQualityOptions(from: htmlString) {
                self.qualityOptions = qualityOptions
                DispatchQueue.main.async {
                    self.selectQuality()
                }
            } else {
                print("No video source found in iframe content")
                self.retryExtraction()
            }
        }
    }
    
    private func extractQualityOptions(from htmlString: String) -> [(label: String, url: URL)]? {
        let pattern = #"var\s+videos\s*=\s*\[(.*?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString)),
              let videosArrayRange = Range(match.range(at: 1), in: htmlString) else {
                  return nil
              }
        
        let videosArrayString = String(htmlString[videosArrayRange])
        let videoObjects = videosArrayString.components(separatedBy: "}, {")
        
        var options: [(label: String, url: URL)] = []
        
        for videoObject in videoObjects {
            let labelPattern = #"label:\s*'(\d+p)'"#
            let srcPattern = #"src:\s*'([^']*)'"#
            
            guard let labelRegex = try? NSRegularExpression(pattern: labelPattern, options: []),
                  let srcRegex = try? NSRegularExpression(pattern: srcPattern, options: []),
                  let labelMatch = labelRegex.firstMatch(in: videoObject, range: NSRange(videoObject.startIndex..., in: videoObject)),
                  let srcMatch = srcRegex.firstMatch(in: videoObject, range: NSRange(videoObject.startIndex..., in: videoObject)),
                  let labelRange = Range(labelMatch.range(at: 1), in: videoObject),
                  let srcRange = Range(srcMatch.range(at: 1), in: videoObject) else {
                      continue
                  }
            
            let label = String(videoObject[labelRange])
            let srcString = String(videoObject[srcRange])
            
            if let url = URL(string: srcString) {
                options.append((label: label, url: url))
            }
        }
        
        return options.isEmpty ? nil : options.sorted { $0.label > $1.label }
    }
    
    private func selectQuality() {
        let preferredQuality = UserDefaults.standard.string(forKey: "preferredQuality") ?? "720p"
        
        if let matchingQuality = qualityOptions.first(where: { $0.label == preferredQuality }) {
            handleVideoURL(url: matchingQuality.url)
        } else if let nearestQuality = findNearestQuality(preferred: preferredQuality) {
            handleVideoURL(url: nearestQuality.url)
        } else {
            showQualityPicker()
        }
    }
    
    private func findNearestQuality(preferred: String) -> (label: String, url: URL)? {
        let preferredValue = Int(preferred.replacingOccurrences(of: "p", with: "")) ?? 0
        let sortedQualities = qualityOptions.sorted { quality1, quality2 in
            let diff1 = abs(Int(quality1.label.replacingOccurrences(of: "p", with: ""))! - preferredValue)
            let diff2 = abs(Int(quality2.label.replacingOccurrences(of: "p", with: ""))! - preferredValue)
            return diff1 < diff2
        }
        return sortedQualities.first
    }
    
    private func showQualityPicker() {
        let alertController = UIAlertController(title: "Select Prefered Quality", message: nil, preferredStyle: .actionSheet)
        
        for option in qualityOptions {
            let action = UIAlertAction(title: option.label, style: .default) { [weak self] _ in
                self?.handleVideoURL(url: option.url)
            }
            alertController.addAction(action)
        }
        
        present(alertController, animated: true, completion: nil)
    }
    
    private func extractIframeSourceURL(from htmlString: String) -> URL? {
        do {
            let doc: Document = try SwiftSoup.parse(htmlString)
            guard let iframeElement = try doc.select("iframe").first(),
                  let sourceURLString = try iframeElement.attr("src").nilIfEmpty,
                  let sourceURL = URL(string: sourceURLString) else {
                      return nil
                  }
            return sourceURL
        } catch {
            print("Error parsing HTML with SwiftSoup: \(error)")
            return nil
        }
    }
    
    private func extractVideoSourceURL(from htmlString: String) -> URL? {
        do {
            let doc: Document = try SwiftSoup.parse(htmlString)
            guard let videoElement = try doc.select("video").first(),
                  let sourceURLString = try videoElement.attr("src").nilIfEmpty,
                  let sourceURL = URL(string: sourceURLString) else {
                      return nil
                  }
            return sourceURL
        } catch {
            print("Error parsing HTML with SwiftSoup: \(error)")
            
            let pattern = #"<video[^>]+src="([^"]+)"#
            
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString)),
                  let urlRange = Range(match.range(at: 1), in: htmlString) else {
                      return nil
                  }
            
            let urlString = String(htmlString[urlRange])
            return URL(string: urlString)
        }
    }
    
    private func handleVideoURL(url: URL) {
        DispatchQueue.main.async {
            self.activityIndicator?.stopAnimating()
            
            if UserDefaults.standard.bool(forKey: "isToDownload") {
                self.handleDownload(url: url)
            }
            else if GCKCastContext.sharedInstance().sessionManager.hasConnectedCastSession() {
                self.castVideoToGoogleCast(videoURL: url)
                self.dismiss(animated: true, completion: nil)
            }
            else if let selectedPlayer = UserDefaults.standard.string(forKey: "mediaPlayerSelected") {
                if selectedPlayer == "VLC" || selectedPlayer == "Infuse" || selectedPlayer == "OutPlayer" || selectedPlayer == "nPlayer" {
                    self.animeDetailsViewController?.openInExternalPlayer(player: selectedPlayer, url: url)
                    self.dismiss(animated: true, completion: nil)
                } else if selectedPlayer == "Custom" {
                    let videoTitle = self.animeDetailsViewController?.animeTitle ?? "Anime"
                    let imageURL = self.animeDetailsViewController?.imageUrl ?? ""
                    let customPlayerVC = CustomPlayerView(videoTitle: videoTitle, videoURL: url, cell: self.cell, fullURL: self.fullURL, image: imageURL)
                    customPlayerVC.modalPresentationStyle = .fullScreen
                    customPlayerVC.delegate = self
                    self.present(customPlayerVC, animated: true, completion: nil)
                } else {
                    self.playOrCastVideo(url: url)
                }
            }
            else {
                self.playOrCastVideo(url: url)
            }
        }
    }
    
    private func handleDownload(url: URL) {
        UserDefaults.standard.set(false, forKey: "isToDownload")
        
        self.dismiss(animated: true, completion: nil)
        
        let downloadManager = DownloadManager.shared
        let title = self.animeDetailsViewController?.animeTitle ?? "Anime Download"
        
        downloadManager.startDownload(
            url: url,
            title: title,
            priority: .normal,
            progress: { progress in
                DispatchQueue.main.async {
                    print("Download progress: \(progress * 100)%")
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let downloadURL):
                        print("Download completed. File saved at: \(downloadURL)")
                        self?.animeDetailsViewController?.showAlert(withTitle: "Download Completed!", message: "You can find your download in the Library -> Downloads.")
                    case .failure(let error):
                        print("Download failed with error: \(error.localizedDescription)")
                        self?.animeDetailsViewController?.showAlert(withTitle: "Download Failed", message: error.localizedDescription)
                    }
                }
            }
        )
    }
    
    private func playOrCastVideo(url: URL) {
        let player = AVPlayer(url: url)
        let playerViewController = NormalPlayer()
        playerViewController.player = player
        self.addChild(playerViewController)
        self.view.addSubview(playerViewController.view)
        
        playerViewController.view.frame = self.view.bounds
        playerViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerViewController.didMove(toParent: self)
        
        let lastPlayedTime = UserDefaults.standard.double(forKey: "lastPlayedTime_\(self.fullURL)")
        
        if lastPlayedTime > 0 {
            player.seek(to: CMTime(seconds: lastPlayedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
        }
        
        player.play()
        
        self.player = player
        self.playerViewController = playerViewController
        self.addPeriodicTimeObserver()
    }
    
    private func castVideoToGoogleCast(videoURL: URL) {
        DispatchQueue.main.async {
            let metadata = GCKMediaMetadata(metadataType: .movie)
            
            if UserDefaults.standard.bool(forKey: "fullTitleCast") {
                if let animeTitle = self.animeDetailsViewController?.animeTitle {
                    metadata.setString(animeTitle, forKey: kGCKMetadataKeyTitle)
                } else {
                    print("Error: Anime title is missing.")
                }
            } else {
                let episodeNumber = (self.animeDetailsViewController?.currentEpisodeIndex ?? -1) + 1
                metadata.setString("Episode \(episodeNumber)", forKey: kGCKMetadataKeyTitle)
            }
            
            if UserDefaults.standard.bool(forKey: "animeImageCast") {
                if let imageURL = URL(string: self.animeDetailsViewController?.imageUrl ?? "") {
                    metadata.addImage(GCKImage(url: imageURL, width: 480, height: 720))
                } else {
                    print("Error: Anime image URL is missing or invalid.")
                }
            }
            
            let builder = GCKMediaInformationBuilder(contentURL: videoURL)
            builder.contentType = "video/mp4"
            builder.metadata = metadata
            
            let streamTypeString = UserDefaults.standard.string(forKey: "castStreamingType") ?? "buffered"
            switch streamTypeString {
            case "live":
                builder.streamType = .live
            default:
                builder.streamType = .buffered
            }
            
            let mediaInformation = builder.build()
            
            if let remoteMediaClient = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient {
                let lastPlayedTime = UserDefaults.standard.double(forKey: "lastPlayedTime_\(self.fullURL)")
                if lastPlayedTime > 0 {
                    let options = GCKMediaLoadOptions()
                    options.playPosition = TimeInterval(lastPlayedTime)
                    remoteMediaClient.loadMedia(mediaInformation, with: options)
                } else {
                    remoteMediaClient.loadMedia(mediaInformation)
                }
            }
        }
    }
    
    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
                  let currentItem = self.player?.currentItem,
                  currentItem.duration.seconds.isFinite else {
                      return
                  }
            
            let currentTime = time.seconds
            let duration = currentItem.duration.seconds
            let progress = currentTime / duration
            let remainingTime = duration - currentTime
            
            self.cell.updatePlaybackProgress(progress: Float(progress), remainingTime: remainingTime)
            
            UserDefaults.standard.set(currentTime, forKey: "lastPlayedTime_\(self.fullURL)")
            UserDefaults.standard.set(duration, forKey: "totalTime_\(self.fullURL)")
            
            if let viewController = self.animeDetailsViewController,
               let episodeNumber = viewController.episodes[safe: viewController.currentEpisodeIndex]?.number {
                
                if let episodeNumberInt = Int(episodeNumber) {
                    let selectedMediaSource = UserDefaults.standard.string(forKey: "selectedMediaSource") ?? "Anime3rb"
                    
                    let continueWatchingItem = ContinueWatchingItem(
                        animeTitle: viewController.animeTitle ?? "Unknown Anime",
                        episodeTitle: "Ep. \(episodeNumberInt)",
                        episodeNumber: episodeNumberInt,
                        imageURL: viewController.imageUrl ?? "",
                        fullURL: self.fullURL,
                        lastPlayedTime: currentTime,
                        totalTime: duration,
                        source: selectedMediaSource
                    )
                    ContinueWatchingManager.shared.saveItem(continueWatchingItem)

                    let shouldSendPushUpdates = UserDefaults.standard.bool(forKey: "sendPushUpdates")

                    if shouldSendPushUpdates && remainingTime / duration < 0.15 && !viewController.hasSentUpdate {
                        let cleanedTitle = viewController.cleanTitle(viewController.animeTitle ?? "Unknown Anime")

                        viewController.fetchAnimeID(title: cleanedTitle) { animeID in
                            let aniListMutation = AniListMutation()
                            aniListMutation.updateAnimeProgress(animeId: animeID, episodeNumber: episodeNumberInt) { result in
                                switch result {
                                case .success():
                                    print("Successfully updated anime progress.")
                                case .failure(let error):
                                    print("Failed to update anime progress: \(error.localizedDescription)")
                                }
                            }
                            
                            viewController.hasSentUpdate = true
                        }
                    }
                } else {
                    print("Error: Failed to convert episodeNumber '\(episodeNumber)' to an Int.")
                }
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func cleanup() {
        player?.pause()
        player = nil
        
        playerViewController?.willMove(toParent: nil)
        playerViewController?.view.removeFromSuperview()
        playerViewController?.removeFromParent()
        playerViewController = nil
        
        if let timeObserverToken = timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
    }
    
    private func retryExtraction() {
        retryCount += 1
        if retryCount < maxRetries {
            print("Retrying extraction (Attempt \(retryCount + 1))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.loadInitialURL()
            }
        } else {
            print("Max retries reached. Unable to find video source.")
            DispatchQueue.main.async {
                self.activityIndicator?.stopAnimating()
                self.dismiss(animated: true)
            }
        }
    }
    
    func playNextEpisode() {
        guard let animeDetailsViewController = self.animeDetailsViewController else {
            print("Error: animeDetailsViewController is nil")
            return
        }
        
        if animeDetailsViewController.isReverseSorted {
            animeDetailsViewController.currentEpisodeIndex -= 1
            if animeDetailsViewController.currentEpisodeIndex >= 0 {
                playEpisode(at: animeDetailsViewController.currentEpisodeIndex)
            } else {
                animeDetailsViewController.currentEpisodeIndex = 0
            }
        } else {
            animeDetailsViewController.currentEpisodeIndex += 1
            if animeDetailsViewController.currentEpisodeIndex < animeDetailsViewController.episodes.count {
                playEpisode(at: animeDetailsViewController.currentEpisodeIndex)
            } else {
                animeDetailsViewController.currentEpisodeIndex = animeDetailsViewController.episodes.count - 1
            }
        }
    }
    
    private func playEpisode(at index: Int) {
        guard let animeDetailsViewController = self.animeDetailsViewController,
              index >= 0 && index < animeDetailsViewController.episodes.count else {
                  return
              }
        
        let nextEpisode = animeDetailsViewController.episodes[index]
        if let cell = animeDetailsViewController.tableView.cellForRow(at: IndexPath(row: index, section: 2)) as? EpisodeCell {
            animeDetailsViewController.episodeSelected(episode: nextEpisode, cell: cell)
        }
    }
    
    @objc func playerItemDidReachEnd(notification: Notification) {
        if UserDefaults.standard.bool(forKey: "AutoPlay") {
            guard let animeDetailsViewController = self.animeDetailsViewController else { return }
            let hasNextEpisode = animeDetailsViewController.isReverseSorted ?
            (animeDetailsViewController.currentEpisodeIndex > 0) :
            (animeDetailsViewController.currentEpisodeIndex < animeDetailsViewController.episodes.count - 1)
            
            if hasNextEpisode {
                self.dismiss(animated: true) { [weak self] in
                    self?.playNextEpisode()
                }
            } else {
                self.dismiss(animated: true, completion: nil)
            }
        } else {
            self.dismiss(animated: true, completion: nil)
        }
    }
}

extension ExternalVideoPlayer3rb: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.absoluteString == streamURL {
            extractIframeSource()
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("WebView navigation failed: \(error.localizedDescription)")
        retryExtraction()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("WebView provisional navigation failed: \(error.localizedDescription)")
        retryExtraction()
    }
}

extension ExternalVideoPlayer3rb: CustomPlayerViewDelegate {
    func customPlayerViewDidDismiss() {
        self.dismiss(animated: true, completion: nil)
    }
}
