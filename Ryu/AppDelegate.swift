import UIKit
import GoogleCast
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        setupDefaultUserPreferences()
        setupGoogleCast()
        checkForFirstLaunch()
        // Access DownloadManager singleton to initialize it
        _ = DownloadManager.shared
        return true
    }
    
    private func setupDefaultUserPreferences() {
        let defaultValues: [String: Any] = [
            "selectedMediaSource": "AnimeWorld",
            "AnimeListingService": "AniList",
            "maxRetries": 10,
            "holdSpeedPlayer": 2,
            "preferredQuality": "1080p",
            "subtitleHiPrefe": "English",
            "serverHiPrefe": "hd-1",
            "audioHiPrefe": "Always Ask",
            "syncWithSystem": true,
            "fullTitleCast": true,
            "animeImageCast": true
        ]
        
        for (key, value) in defaultValues {
            if UserDefaults.standard.object(forKey: key) == nil {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        
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
                   let window = windowScene.windows.first {
                    let onboardingVC = OnboardingViewController()
                    onboardingVC.modalPresentationStyle = .fullScreen
                    window.rootViewController?.present(onboardingVC, animated: true)
                }
            }
        }
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if url.scheme == "ryu" {
             if url.host == "anilist-callback", let queryParams = url.queryParameters, let code = queryParams["code"] {
                NotificationCenter.default.post(name: Notification.Name("AuthorizationCodeReceived"), object: nil, userInfo: ["code": code])
                return true
            }
            // Handle other potential ryu:// URLs if needed
        }
        return GCKCastContext.sharedInstance().application(app, open: url, options: options) // Allow Cast SDK to handle URLs if needed
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
