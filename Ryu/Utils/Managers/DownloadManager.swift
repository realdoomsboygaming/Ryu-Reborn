// Ryu/Utils/Managers/DownloadManager.swift
import Foundation
import AVFoundation
import Combine
import UserNotifications

// Define DownloadItem struct within the same file scope
struct DownloadItem: Identifiable, Codable {
    let id: String // Unique identifier (e.g., source URL string or UUID)
    let title: String // User-friendly title (e.g., "Anime Title - Ep 1")
    let sourceURL: URL // Original URL to download from
    var downloadTaskIdentifier: Int? // To map URLSession delegate calls back to the item
    var progress: Float = 0.0
    var status: DownloadStatus = .pending
    var format: DownloadFormat
    var completedFileURL: URL? // Local URL (file path for MP4, asset location for HLS)
    var totalBytesExpected: Int64? // For progress calculation if available
    var totalBytesWritten: Int64?  // For progress calculation if available
    var errorDescription: String? // Store error message on failure

    enum DownloadStatus: String, Codable {
        case pending      // Waiting to start
        case downloading  // Actively downloading
        case paused       // Download paused (Optional TODO)
        case completed    // Download finished successfully
        case failed       // Download failed
        case cancelled    // Download cancelled by user
    }

    enum DownloadFormat: String, Codable {
        case mp4
        case hls
        case unknown
    }

    // CodingKeys needed because downloadTaskIdentifier is optional and potentially transient if not persisted
    enum CodingKeys: String, CodingKey {
        case id, title, sourceURL, progress, status, format, completedFileURL, totalBytesExpected, totalBytesWritten, errorDescription
        // Exclude downloadTaskIdentifier from Codable persistence if desired
    }

    // Helper to get a displayable progress string
    var progressString: String {
        String(format: "%.0f%%", progress * 100)
    }

    // Helper to get file size string if available
    var fileSizeString: String {
        guard let totalBytes = totalBytesExpected, totalBytes > 0 else { return "N/A" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}


class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var activeDownloads: [String: DownloadItem] = [:] // Keyed by DownloadItem.id
    @Published private(set) var completedDownloads: [DownloadItem] = []

    private var mp4Session: URLSession!
    private var hlsSession: AVAssetDownloadURLSession!

    private var sessionIdentifierMP4 = "me.ryu.mp4downloadsession"
    private var sessionIdentifierHLS = "me.ryu.hlsdownloadsession"

    // To store completion handlers for background tasks
    var backgroundCompletionHandler: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    // Make init private for Singleton pattern
    private override init() {
        super.init()
        
        // Configure MP4 session
        let mp4Config = URLSessionConfiguration.background(withIdentifier: sessionIdentifierMP4)
        mp4Config.isDiscretionary = false // Allow downloads on cellular, etc. (Consider user setting later)
        mp4Config.sessionSendsLaunchEvents = true
        mp4Session = URLSession(configuration: mp4Config, delegate: self, delegateQueue: nil)

        // Configure HLS session
        let hlsConfig = URLSessionConfiguration.background(withIdentifier: sessionIdentifierHLS)
        hlsConfig.isDiscretionary = false
        hlsConfig.sessionSendsLaunchEvents = true
        // Important: Assign AVAssetDownloadDelegate
        hlsSession = AVAssetDownloadURLSession(configuration: hlsConfig, assetDownloadDelegate: self, delegateQueue: nil)

        loadCompletedDownloads()
        restoreActiveDownloads() // Attempt to restore state after app launch
        
        // Request notification permission on init
        requestNotificationPermission()
    }
    
    // MARK: - Public API

    func startDownload(url: URL, title: String) {
        let downloadId = url.absoluteString // Use URL as unique ID for simplicity
        
        guard activeDownloads[downloadId] == nil || activeDownloads[downloadId]?.status == .failed || activeDownloads[downloadId]?.status == .cancelled else {
            print("Download for \(title) already in progress or queued.")
            return
        }
        
        let format: DownloadItem.DownloadFormat
        if url.pathExtension.lowercased() == "m3u8" {
            format = .hls
        } else if url.pathExtension.lowercased() == "mp4" {
             format = .mp4
        } else {
            print("Warning: Unknown file format for \(url). Assuming MP4.")
            format = .mp4 // Treat unknown as MP4
        }

        var newItem = DownloadItem(id: downloadId, title: title, sourceURL: url, format: format)
        newItem.status = .pending
        
        // Add/Update in active downloads immediately to show in UI
        DispatchQueue.main.async {
            self.activeDownloads[downloadId] = newItem
        }

        // Initiate the correct download task
        if format == .hls {
            startHLSDownload(item: &newItem)
        } else { // MP4 or Unknown (treated as MP4)
            startMP4Download(item: &newItem)
        }
    }

    func cancelDownload(for downloadId: String) {
        guard var item = activeDownloads[downloadId] else { return }

        if let taskIdentifier = item.downloadTaskIdentifier {
            findAndCancelTask(identifier: taskIdentifier, format: item.format)
        }
        
        item.status = .cancelled
        DispatchQueue.main.async {
            self.activeDownloads.removeValue(forKey: downloadId) // Remove cancelled download
        }
        print("Cancelled download for \(item.title)")
    }

    // Get active downloads for UI
    func getActiveDownloadItems() -> [DownloadItem] {
        return Array(activeDownloads.values).sorted { $0.title < $1.title } // Or sort by date added etc.
    }
    
    // Get completed downloads for UI
    func getCompletedDownloadItems() -> [DownloadItem] {
        return completedDownloads.sorted { ($0.completedFileURL?.path ?? "") < ($1.completedFileURL?.path ?? "") } // Or sort by date completed etc.
    }
    
    // Delete a completed download
    func deleteCompletedDownload(item: DownloadItem) {
        guard let urlToDelete = item.completedFileURL else {
            print("Error: No file URL for completed download \(item.title)")
            return
        }
        
        do {
            // For HLS, the URL points to directory structure, remove that
             if item.format == .hls {
                // AVFoundation manages HLS storage internally, try deleting the bookmark location
                 try FileManager.default.removeItem(at: urlToDelete)
                 print("Attempted to remove HLS asset location at \(urlToDelete.path)")
             } else {
                 // For MP4, delete the file directly
                 try FileManager.default.removeItem(at: urlToDelete)
                 print("Deleted MP4 file at \(urlToDelete.path)")
             }

            // Remove from completed list and update UI
            if let index = completedDownloads.firstIndex(where: { $0.id == item.id }) {
                completedDownloads.remove(at: index)
                saveCompletedDownloads() // Persist the change
                // Manually publish change since direct array mutation isn't automatically published
                 DispatchQueue.main.async {
                    // This forces the @Published property to emit a change
                    self.completedDownloads = self.completedDownloads
                }
            }
        } catch {
            print("Error deleting file/asset for \(item.title) at \(urlToDelete): \(error)")
            // Optionally show error to user
        }
    }

    // MARK: - Internal Download Logic

    private func startMP4Download(item: inout DownloadItem) {
        let task = mp4Session.downloadTask(with: item.sourceURL)
        item.downloadTaskIdentifier = task.taskIdentifier // Store the identifier
        item.status = .downloading
        
        DispatchQueue.main.async {
            self.activeDownloads[item.id] = item // Update with task ID and status
        }
        task.resume()
        print("Started MP4 download for \(item.title) (Task ID: \(task.taskIdentifier))")
    }

    private func startHLSDownload(item: inout DownloadItem) {
        let asset = AVURLAsset(url: item.sourceURL)
        
        // Use title to create a unique local asset identifier
        let safeTitle = item.title.replacingOccurrences(of: "[^a-zA-Z0-9_.]", with: "_", options: .regularExpression)
        
        // Create download task
        guard let task = hlsSession.makeAssetDownloadTask(asset: asset,
                                                          assetTitle: safeTitle,
                                                          assetArtworkData: nil, // Optional artwork
                                                          options: nil) else { // Options for quality selection can be added here
            print("Failed to create AVAssetDownloadTask for \(item.title)")
            item.status = .failed
            item.errorDescription = "Failed to create HLS download task."
            DispatchQueue.main.async {
                self.activeDownloads[item.id] = item
            }
            return
        }
        
        item.downloadTaskIdentifier = task.taskIdentifier
        item.status = .downloading
        
        DispatchQueue.main.async {
             self.activeDownloads[item.id] = item // Update with task ID and status
        }
        task.resume()
        print("Started HLS download for \(item.title) (Task ID: \(task.taskIdentifier))")
    }

    private func findAndCancelTask(identifier: Int, format: DownloadItem.DownloadFormat) {
        let session = (format == .hls) ? hlsSession : mp4Session
        session?.getAllTasks { tasks in
            if let task = tasks.first(where: { $0.taskIdentifier == identifier }) {
                task.cancel()
                print("Found and cancelled task \(identifier)")
            } else {
                 print("Could not find task \(identifier) to cancel")
            }
        }
    }

    // MARK: - Persistence

    private func completedDownloadsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("completedDownloads.json")
    }

    private func saveCompletedDownloads() {
        do {
            let data = try JSONEncoder().encode(completedDownloads)
            try data.write(to: completedDownloadsURL())
        } catch {
            print("Error saving completed downloads: \(error)")
        }
    }

    private func loadCompletedDownloads() {
        guard let data = try? Data(contentsOf: completedDownloadsURL()) else { return }
        // No do-catch needed here as try? handles the error
        if let decodedDownloads = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            completedDownloads = decodedDownloads
            print("Loaded \(completedDownloads.count) completed downloads.")
        } else {
            print("Error loading completed downloads: Decoding failed.")
            // Handle error, e.g., delete corrupt file
            try? FileManager.default.removeItem(at: completedDownloadsURL())
        }
    }
    
    // MARK: - State Restoration (Basic)
    
    private func restoreActiveDownloads() {
       // When the app launches, query sessions for existing tasks
       mp4Session.getAllTasks { tasks in
           print("Found \(tasks.count) MP4 background tasks.")
           // TODO: Match tasks to persisted DownloadItems if implementing full resume
           // For now, we just log them. The delegates will handle updates if they resume.
       }
       hlsSession.getAllTasks { tasks in
           print("Found \(tasks.count) HLS background tasks.")
            // TODO: Match tasks to persisted DownloadItems if implementing full resume
           // AVAssetDownloadTask automatically handles resuming in many cases
       }
   }

    // MARK: - Notifications
    
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            } else if !granted {
                print("Notification permission not granted.")
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil) // Unique ID per notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
     // Helper to generate unique file names
    private func getUniqueFileURL(for fileName: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var finalURL = directory.appendingPathComponent(fileName)
        var counter = 1
        
        // Ensure directory exists
         do {
             try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
         } catch {
             print("Error creating documents directory: \(error)")
             // Fallback or handle error
         }

        while fileManager.fileExists(atPath: finalURL.path) {
            let name = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            // Ensure extension is not empty before adding dot
            let newName = ext.isEmpty ? "\(name)_\(counter)" : "\(name)_\(counter).\(ext)"
            finalURL = directory.appendingPathComponent(newName)
            counter += 1
        }
        return finalURL
    }
}

// MARK: - URLSessionDownloadDelegate (for MP4)
extension DownloadManager: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Use taskIdentifier directly from the downloadTask parameter
        guard let taskIdentifier = downloadTask.taskIdentifier as Int?,
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
              var item = activeDownloads[downloadId] else {
            print("Error: Finished download task \(String(describing: downloadTask.taskIdentifier)) not found in active downloads.")
            try? FileManager.default.removeItem(at: location) // Clean up temp file
            return
        }

        // Generate a unique destination URL in Documents
        let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let originalFileName = downloadTask.originalRequest?.url?.lastPathComponent ?? "\(item.title).mp4" // Use title as fallback
        let safeFileName = originalFileName.replacingOccurrences(of: "[^a-zA-Z0-9_.]", with: "_", options: .regularExpression)
        let destinationURL = getUniqueFileURL(for: safeFileName, in: documentsDirectoryURL)

        do {
            // Move the downloaded file from the temporary location to the final destination
            try FileManager.default.moveItem(at: location, to: destinationURL)
            print("MP4 File moved to: \(destinationURL.path)")

            // Update item state
            item.status = .completed
            item.progress = 1.0
            item.completedFileURL = destinationURL
            item.downloadTaskIdentifier = nil // Task is finished
            
            // Move from active to completed
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: downloadId)
                self.completedDownloads.append(item)
                self.saveCompletedDownloads() // Persist the change
                // Manually publish change
                 self.completedDownloads = self.completedDownloads
            }

            sendNotification(title: "Download Complete", body: "\(item.title) has finished downloading.")
            NotificationCenter.default.post(name: .downloadCompleted, object: nil, userInfo: ["title": item.title])

        } catch {
            print("Error moving MP4 file for \(item.title): \(error)")
            item.status = .failed
            item.errorDescription = error.localizedDescription
            item.downloadTaskIdentifier = nil
             DispatchQueue.main.async {
                 // Update status in activeDownloads
                 self.activeDownloads[downloadId] = item
             }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        
        guard totalBytesExpectedToWrite > 0, // Avoid division by zero
              let taskIdentifier = downloadTask.taskIdentifier as Int?, // Use taskIdentifier directly
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
              var item = activeDownloads[downloadId] else {
                  return
              }

        item.progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        item.totalBytesWritten = totalBytesWritten
        item.totalBytesExpected = totalBytesExpectedToWrite
        item.status = .downloading // Ensure status is downloading
        
        // Update active downloads (debouncing might be good here for high frequency updates)
        DispatchQueue.main.async {
             // Check if the item still exists before updating
             if self.activeDownloads[downloadId] != nil {
                 self.activeDownloads[downloadId] = item
             }
        }
    }
}

// MARK: - AVAssetDownloadDelegate (for HLS)
extension DownloadManager: AVAssetDownloadDelegate {
    
    // Called when the download finishes successfully.
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
         // Use taskIdentifier directly from the assetDownloadTask parameter
        guard let taskIdentifier = assetDownloadTask.taskIdentifier as Int?,
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
              var item = activeDownloads[downloadId] else {
            print("Error: Finished HLS download task \(String(describing: assetDownloadTask.taskIdentifier)) not found in active downloads.")
            return
        }
        
        item.status = .completed
        item.progress = 1.0
        item.completedFileURL = location // Store the asset location URL
        item.downloadTaskIdentifier = nil // Task is finished
        
         // Move from active to completed
        DispatchQueue.main.async {
            self.activeDownloads.removeValue(forKey: downloadId)
            self.completedDownloads.append(item)
            self.saveCompletedDownloads() // Persist
             // Manually publish change
             self.completedDownloads = self.completedDownloads
        }

        print("HLS Download finished for \(item.title). Asset location: \(location)")
        sendNotification(title: "Download Complete", body: "\(item.title) has finished downloading.")
        NotificationCenter.default.post(name: .downloadCompleted, object: nil, userInfo: ["title": item.title])
    }

    // Called periodically with progress updates.
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        
        guard let taskIdentifier = assetDownloadTask.taskIdentifier as Int?, // Use taskIdentifier directly
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
              var item = activeDownloads[downloadId] else { return }
              
        var percentComplete: Float = 0.0
        if timeRangeExpectedToLoad.duration.seconds > 0 {
             var totalDurationLoaded: Double = 0
            for value in totalTimeRangesLoaded {
                let loadedTimeRange = value.timeRangeValue
                totalDurationLoaded += loadedTimeRange.duration.seconds
            }
            // Clamp progress between 0 and 1
            percentComplete = Float(min(max(0.0, totalDurationLoaded / timeRangeExpectedToLoad.duration.seconds), 1.0))
        }

        item.progress = percentComplete
        item.status = .downloading // Ensure status
        
        DispatchQueue.main.async {
             // Check if the item still exists before updating
             if self.activeDownloads[downloadId] != nil {
                 self.activeDownloads[downloadId] = item
             }
        }
    }
    
    // Optional: Handle variant/media selection if needed
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didResolve resolvedMediaSelection: AVMediaSelection) {
        // You could potentially inspect resolvedMediaSelection here if you need to know
        // which specific audio/subtitle tracks were chosen for download.
        print("HLS media selection resolved for task \(assetDownloadTask.taskIdentifier)")
    }
}


// MARK: - URLSessionTaskDelegate (Common error handling)
extension DownloadManager: URLSessionTaskDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
         // Use taskIdentifier directly from task
         guard let taskIdentifier = task.taskIdentifier as Int?,
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
              var item = activeDownloads[downloadId] else {
            if error != nil {
                 print("Error for untracked task \(String(describing: task.taskIdentifier)): \(error!.localizedDescription)")
            }
            return
        }

        // This needs to be set before updating the state on the main thread
        let originalTaskIdentifier = item.downloadTaskIdentifier
        item.downloadTaskIdentifier = nil // Clear task ID as it's finished

        DispatchQueue.main.async {
            // Re-fetch item in case it was updated by another delegate call
             guard var currentItem = self.activeDownloads[downloadId] else { return }
             
             // Ensure we only process the completion for the *correct* task if ID somehow got reused (unlikely with background sessions)
             guard currentItem.downloadTaskIdentifier == originalTaskIdentifier || originalTaskIdentifier != nil else { // Allow nil if it was already cleared
                 print("Task \(taskIdentifier) completion ignored, item may have been restarted.")
                 return
             }
            
            currentItem.downloadTaskIdentifier = nil // Ensure it's cleared on main thread too

            if let error = error {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                     currentItem.status = .cancelled
                    print("Task \(taskIdentifier) (\(currentItem.title)) was cancelled.")
                    self.activeDownloads.removeValue(forKey: downloadId) // Remove if cancelled
                } else {
                    currentItem.status = .failed
                    currentItem.errorDescription = error.localizedDescription
                    print("Task \(taskIdentifier) (\(currentItem.title)) failed: \(error.localizedDescription)")
                    self.sendNotification(title: "Download Failed", body: "Failed to download \(currentItem.title): \(error.localizedDescription)")
                    // Keep in activeDownloads but update status to failed
                    self.activeDownloads[downloadId] = currentItem
                }
            } else {
                // Success case is handled by specific download delegates.
                // If status is still downloading here, something went wrong.
                if currentItem.status == .downloading {
                    print("Warning: Task \(taskIdentifier) (\(currentItem.title)) completed without error but wasn't marked completed by specific delegates.")
                     currentItem.status = .failed // Mark as failed if it wasn't properly completed
                     currentItem.errorDescription = "Download finished unexpectedly."
                     self.activeDownloads[downloadId] = currentItem
                     self.sendNotification(title: "Download Failed", body: "\(currentItem.title) finished unexpectedly.")
                }
            }
        }
    }
}

// MARK: - URLSessionDelegate (For background session events)
extension DownloadManager: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            // Call the completion handler stored by the AppDelegate
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
            print("Finished events for background session: \(session.configuration.identifier ?? "N/A")")
        }
    }
}
