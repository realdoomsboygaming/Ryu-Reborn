import UIKit
import GoogleCast
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        setupDefaultUserPreferences()
        setupGoogleCast()
        checkForFirstLaunch()
        _ = DownloadManager.shared // Initialize DownloadManager
        return true
    }
    
    private func setupDefaultUserPreferences() {
        let defaultValues: [String: Any] = [
            "selectedMediaSource": "AnimeWorld",
            "AnimeListingService": "AniList",
            "maxRetries": 10,
            "holdSpeedPlayer": 2.0, // Ensure it's float/double
            "preferredQuality": "1080p",
            "subtitleHiPrefe": "English",
            "serverHiPrefe": "hd-1",
            "audioHiPrefe": "Always Ask",
            "syncWithSystem": true,
            "fullTitleCast": true,
            "animeImageCast": true,
            "isEpisodeReverseSorted": false,
            "AutoPlay": true,
            "AlwaysLandscape": false,
            "browserPlayer": false,
            "mergeWatching": false,
            "notificationEpisodes": true,
            "sendPushUpdates": true, // Default for AniList tracking
            "autoSkipIntro": true,
            "autoSkipOutro": true,
            "skipFeedbacks": true,
            "customAnimeSkipInstance": false,
            "savedAniSkipInstance": "",
            "googleTranslation": true,
            "translationLanguage": "en",
            "customTranslatorInstance": false,
            "savedTranslatorInstance": "",
            "otherFormats": false, // TokyoInsider setting
            "gogoFetcher": "Default", // GoGoAnime setting
            "castStreamingType": "buffered" // Cast setting
            // Add other defaults as needed
        ]
        
        for (key, value) in defaultValues {
            if UserDefaults.standard.object(forKey: key) == nil {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        
        // Cleanup old keys if necessary
        if UserDefaults.standard.object(forKey: "accessToken") != nil {
            UserDefaults.standard.removeObject(forKey: "accessToken")
        }
        
        if UserDefaults.standard.string(forKey: "mediaPlayerSelected") == "Experimental" {
            UserDefaults.standard.set("Custom", forKey: "mediaPlayerSelected")
        }
        if UserDefaults.standard.string(forKey: "preferredQuality") == "320p" {
            UserDefaults.standard.set("360p", forKey: "preferredQuality")
        }
    }
    
    private func setupGoogleCast() {
        let options = GCKCastOptions(discoveryCriteria: GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID))
        GCKCastContext.setSharedInstanceWith(options)
    }
    
    func checkForFirstLaunch() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        if !hasCompletedOnboarding {
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootVC = window.rootViewController {
                    
                    // Check if onboarding is already presented
                    if rootVC.presentedViewController is OnboardingViewController {
                        return
                    }
                    
                    let onboardingVC = OnboardingViewController()
                    onboardingVC.modalPresentationStyle = .fullScreen
                    rootVC.present(onboardingVC, animated: true)
                }
            }
        }
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        // Handle your custom URL scheme
        if url.scheme == "ryu", url.host == "anilist", let queryParams = url.queryParameters, let code = queryParams["code"] {
            NotificationCenter.default.post(name: Notification.Name("AuthorizationCodeReceived"), object: nil, userInfo: ["code": code])
            return true // Indicate you handled the URL
        }

        // Allow Google Cast SDK to handle its URLs
        // Note: The signature GCKCastContext.sharedInstance().application(...) might be outdated.
        // Check current Google Cast SDK documentation if casting via URL scheme is needed.
        // Usually, the Cast SDK works through network discovery rather than URL schemes.
        // If the Cast SDK doesn't provide this method anymore, simply remove the line below.
        // For now, let's comment it out as it caused the build error.
        // return GCKCastContext.sharedInstance().application(app, open: url, options: options)

        // If it's not your URL scheme or Cast's (if handled), return false.
        return false
    }
    
    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
    }

    // Pass the completion handler to the DownloadManager
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Store the completion handler in DownloadManager
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
    }

    func applicationWillTerminate(_ application: UIApplication) {
        UserDefaults.standard.set(false, forKey: "isToDownload")
        deleteTemporaryDirectory()
    }

    func deleteTemporaryDirectory() {
        let fileManager = FileManager.default
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        
        do {
            let tmpContents = try fileManager.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil, options: [])
            
            for fileURL in tmpContents {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            print("Error clearing tmp folder: \(error.localizedDescription)")
        }
    }
}
