import Foundation
import AVFoundation
import Combine
import UserNotifications

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

    enum CodingKeys: String, CodingKey {
        case id, title, sourceURL, progress, status, format, completedFileURL, totalBytesExpected, totalBytesWritten, errorDescription
    }

    var progressString: String {
        String(format: "%.0f%%", progress * 100)
    }

    var fileSizeString: String {
        guard let totalBytes = totalBytesExpected, totalBytes > 0 else { return "N/A" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}


class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var activeDownloads: [String: DownloadItem] = [:]
    @Published private(set) var completedDownloads: [DownloadItem] = []

    private var mp4Session: URLSession!
    private var hlsSession: AVAssetDownloadURLSession!

    private var sessionIdentifierMP4 = "me.ryu.mp4downloadsession"
    private var sessionIdentifierHLS = "me.ryu.hlsdownloadsession"

    var backgroundCompletionHandler: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()

        let mp4Config = URLSessionConfiguration.background(withIdentifier: sessionIdentifierMP4)
        mp4Config.isDiscretionary = false
        mp4Config.sessionSendsLaunchEvents = true
        mp4Session = URLSession(configuration: mp4Config, delegate: self, delegateQueue: nil)

        let hlsConfig = URLSessionConfiguration.background(withIdentifier: sessionIdentifierHLS)
        hlsConfig.isDiscretionary = false
        hlsConfig.sessionSendsLaunchEvents = true
        hlsSession = AVAssetDownloadURLSession(configuration: hlsConfig, assetDownloadDelegate: self, delegateQueue: OperationQueue()) // Use OperationQueue for HLS delegate

        loadCompletedDownloads()
        restoreActiveDownloads()
        requestNotificationPermission()
    }

    func startDownload(url: URL, title: String) {
        let downloadId = url.absoluteString

        // Use DispatchQueue.main.sync to safely check and update activeDownloads
        // This prevents race conditions if startDownload is called rapidly multiple times.
        DispatchQueue.main.sync {
            guard activeDownloads[downloadId] == nil ||
                  activeDownloads[downloadId]?.status == .failed ||
                  activeDownloads[downloadId]?.status == .cancelled else {
                print("Download for \(title) already in progress or completed successfully.")
                return // Exit if already active or completed
            }

            let format: DownloadItem.DownloadFormat
            if url.pathExtension.lowercased() == "m3u8" {
                format = .hls
            } else if url.pathExtension.lowercased() == "mp4" {
                 format = .mp4
            } else {
                print("Warning: Unknown file format for \(url). Assuming MP4.")
                format = .mp4
            }

            var newItem = DownloadItem(id: downloadId, title: title, sourceURL: url, format: format)
            newItem.status = .pending

            // Add/Update in active downloads *before* starting task
            self.activeDownloads[downloadId] = newItem
            updateDownloadViewsOnMainThread() // Update UI to show pending state

            // Now start the appropriate download task
            if format == .hls {
                startHLSDownload(item: &newItem) // Pass as inout
            } else {
                startMP4Download(item: &newItem) // Pass as inout
            }
        }
    }

    func cancelDownload(for downloadId: String) {
        DispatchQueue.main.sync { // Ensure thread safety for dictionary access
            guard var item = activeDownloads[downloadId] else { return }

            if let taskIdentifier = item.downloadTaskIdentifier {
                findAndCancelTask(identifier: taskIdentifier, format: item.format)
            }

            item.status = .cancelled
            item.downloadTaskIdentifier = nil // Clear task ID on cancel
            activeDownloads.removeValue(forKey: downloadId)
            updateDownloadViewsOnMainThread() // Update UI after removal
            print("Cancelled download for \(item.title)")
        }
    }

    // Helper to ensure UI updates happen on the main thread
    private func updateDownloadViewsOnMainThread() {
         DispatchQueue.main.async {
             // Post a notification or directly update UI if reference is held
             NotificationCenter.default.post(name: .downloadListUpdated, object: nil)
             // You might replace this with a more direct UI update if needed
         }
     }

    func getActiveDownloadItems() -> [DownloadItem] {
        // Access dictionary on main thread for consistency if modified elsewhere
        var items: [DownloadItem] = []
        DispatchQueue.main.sync {
            items = Array(activeDownloads.values).sorted { $0.title < $1.title }
        }
        return items
    }

    func getCompletedDownloadItems() -> [DownloadItem] {
        // Assume completedDownloads is managed safely or accessed on main thread
        return completedDownloads.sorted { ($0.completedFileURL?.lastPathComponent ?? "") < ($1.completedFileURL?.lastPathComponent ?? "") }
    }

    func deleteCompletedDownload(item: DownloadItem) {
        guard let urlToDelete = item.completedFileURL else {
            print("Error: No file URL for completed download \(item.title)")
            return
        }

        do {
             if item.format == .hls {
                 // For HLS, AVFoundation manages files; removing reference might be enough.
                 // Actual deletion is complex and might require specific asset management.
                 print("Removing HLS reference for \(item.title) at \(urlToDelete.path)")
             } else {
                 try FileManager.default.removeItem(at: urlToDelete)
                 print("Deleted MP4 file at \(urlToDelete.path)")
             }

            if let index = completedDownloads.firstIndex(where: { $0.id == item.id }) {
                completedDownloads.remove(at: index)
                saveCompletedDownloads()
                updateDownloadViewsOnMainThread()
            }
        } catch {
            print("Error deleting file/asset for \(item.title) at \(urlToDelete): \(error)")
        }
    }

     func updateCompletedDownload(item: DownloadItem) {
         if let index = completedDownloads.firstIndex(where: { $0.id == item.id }) {
             completedDownloads[index] = item
             saveCompletedDownloads()
             updateDownloadViewsOnMainThread()
         }
     }

    // No longer needs inout, operates on a copy, updates dictionary on main thread
    private func startMP4Download(item: DownloadItem) {
        let task = mp4Session.downloadTask(with: item.sourceURL)
        var updatedItem = item // Create a mutable copy
        updatedItem.downloadTaskIdentifier = task.taskIdentifier
        updatedItem.status = .downloading

        DispatchQueue.main.async {
            // Check if the item still exists and update it
            if self.activeDownloads[updatedItem.id] != nil {
                self.activeDownloads[updatedItem.id] = updatedItem
                self.updateDownloadViewsOnMainThread() // Update UI after state change
            } else {
                print("Warning: Download item \(updatedItem.id) was removed before task could be associated.")
                task.cancel() // Cancel the task if the item was removed
                return
            }
        }

        task.resume()
        print("Started MP4 download for \(updatedItem.title) (Task ID: \(task.taskIdentifier))")
    }

    // No longer needs inout, operates on a copy, updates dictionary on main thread
    private func startHLSDownload(item: DownloadItem) {
        let asset = AVURLAsset(url: item.sourceURL)
        // Ensure title is filesystem safe
        let safeTitle = item.title.replacingOccurrences(of: "[^a-zA-Z0-9_.-]", with: "_", options: .regularExpression)

        var updatedItem = item // Create a mutable copy

        // Note: options parameter can be used for HLS specific settings if needed
        guard let task = hlsSession.makeAssetDownloadTask(asset: asset,
                                                          assetTitle: safeTitle,
                                                          assetArtworkData: nil,
                                                          options: nil) else {
            print("Failed to create AVAssetDownloadTask for \(item.title)")
            updatedItem.status = .failed
            updatedItem.errorDescription = "Failed to create HLS download task."

            DispatchQueue.main.async {
                // Update the item with the failure status
                if self.activeDownloads[updatedItem.id] != nil {
                     self.activeDownloads[updatedItem.id] = updatedItem
                     self.updateDownloadViewsOnMainThread()
                }
            }
            return
        }

        updatedItem.downloadTaskIdentifier = task.taskIdentifier
        updatedItem.status = .downloading

        DispatchQueue.main.async {
            // Check if the item still exists and update it
             if self.activeDownloads[updatedItem.id] != nil {
                 self.activeDownloads[updatedItem.id] = updatedItem
                 self.updateDownloadViewsOnMainThread()
             } else {
                 print("Warning: Download item \(updatedItem.id) was removed before HLS task could be associated.")
                 task.cancel() // Cancel the task if the item was removed
                 return
             }
        }
        task.resume()
        print("Started HLS download for \(updatedItem.title) (Task ID: \(task.taskIdentifier))")
    }

    private func findAndCancelTask(identifier: Int, format: DownloadItem.DownloadFormat) {
        let session = (format == .hls) ? hlsSession : mp4Session
        session?.getAllTasks { tasks in
            DispatchQueue.main.async { // Ensure UI/state updates happen on main thread
                 if let task = tasks.first(where: { $0.taskIdentifier == identifier }) {
                     task.cancel()
                     print("Found and cancelled task \(identifier)")
                 } else {
                     print("Could not find task \(identifier) to cancel")
                 }
            }
        }
    }

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
        if let decodedDownloads = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            completedDownloads = decodedDownloads
            print("Loaded \(completedDownloads.count) completed downloads.")
            updateDownloadViewsOnMainThread() // Update UI after loading
        } else {
            print("Error loading completed downloads: Decoding failed.")
            try? FileManager.default.removeItem(at: completedDownloadsURL())
        }
    }

    private func restoreActiveDownloads() {
       // This might need more robust logic to re-associate tasks with DownloadItems
       // For now, just logging the tasks found.
       mp4Session.getAllTasks { tasks in
           print("Found \(tasks.count) MP4 background tasks on restore.")
       }
       hlsSession.getAllTasks { tasks in
           print("Found \(tasks.count) HLS background tasks on restore.")
       }
       // Potentially iterate through tasks and try to match them with persisted DownloadItems
       // based on originalRequest URL or other identifiers if you store them.
   }

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

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    // Consolidated file URL generation
    private func getUniqueFileURL(for fileName: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var finalURL = directory.appendingPathComponent(fileName)
        var counter = 1

         do {
             // Ensure the directory exists
             try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
         } catch {
             print("Error creating documents directory: \(error)")
             // Fallback or handle error appropriately
         }

        // Create unique filename if necessary
        while fileManager.fileExists(atPath: finalURL.path) {
            let name = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
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
        guard let taskIdentifier = downloadTask.taskIdentifier as Int? else {
             print("Error: Could not get task identifier for finished MP4 download.")
             try? FileManager.default.removeItem(at: location) // Clean up temp file
             return
         }

        // Find item on main thread for safety
        DispatchQueue.main.sync {
            guard let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
                  var item = activeDownloads[downloadId] else {
                print("Error: Finished MP4 download task \(taskIdentifier) not found in active downloads.")
                try? FileManager.default.removeItem(at: location)
                return
            }

            let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            // Use a safe filename based on the item title
             let safeFileNameBase = item.title.replacingOccurrences(of: "[^a-zA-Z0-9_.-]", with: "_", options: .regularExpression)
             let safeFileName = "\(safeFileNameBase).mp4" // Ensure mp4 extension
            let destinationURL = getUniqueFileURL(for: safeFileName, in: documentsDirectoryURL)

            do {
                try FileManager.default.moveItem(at: location, to: destinationURL)
                print("MP4 File moved to: \(destinationURL.path)")

                item.status = .completed
                item.progress = 1.0
                item.completedFileURL = destinationURL
                item.downloadTaskIdentifier = nil // Clear task ID on completion
                item.errorDescription = nil // Clear any previous error

                // Update state: remove from active, add to completed
                activeDownloads.removeValue(forKey: downloadId)
                completedDownloads.append(item)
                saveCompletedDownloads()
                updateDownloadViewsOnMainThread() // Update UI

                sendNotification(title: "Download Complete", body: "\(item.title) has finished downloading.")
                // Post specific completion notification if needed by UI
                 NotificationCenter.default.post(name: .downloadCompleted, object: nil, userInfo: ["id": item.id, "title": item.title])

            } catch {
                print("Error moving MP4 file for \(item.title): \(error)")
                item.status = .failed
                item.errorDescription = error.localizedDescription
                item.downloadTaskIdentifier = nil // Clear task ID on failure
                // Keep the item in activeDownloads with failed status
                 activeDownloads[downloadId] = item
                 updateDownloadViewsOnMainThread()
                sendNotification(title: "Download Failed", body: "Failed to save \(item.title).")
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {

        guard totalBytesExpectedToWrite > 0, // Ensure total size is valid
              let taskIdentifier = downloadTask.taskIdentifier as Int? else {
            return // Exit if total size is unknown or task ID is missing
        }

        // Perform dictionary lookup and update on the main thread for safety
        DispatchQueue.main.async { [weak self] in
             guard let self = self,
                  let downloadId = self.activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
                  var item = self.activeDownloads[downloadId] else {
                // Item might have been cancelled or completed already
                return
            }

            // Only update if the status is still downloading or pending
            guard item.status == .downloading || item.status == .pending else { return }

            item.progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
            item.totalBytesWritten = totalBytesWritten
            item.totalBytesExpected = totalBytesExpectedToWrite
            item.status = .downloading // Ensure status is downloading

            // Update the item back in the dictionary
            self.activeDownloads[downloadId] = item
            // Optionally, throttle UI updates here if needed for performance
             // self.updateDownloadViewsOnMainThread() // Consider if needed every progress update
        }
    }
}

// MARK: - AVAssetDownloadDelegate (for HLS)
extension DownloadManager: AVAssetDownloadDelegate {

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskIdentifier = assetDownloadTask.taskIdentifier as Int? else {
             print("Error: Could not get task identifier for finished HLS download.")
             return
        }

        // Find item on main thread
        DispatchQueue.main.sync {
            guard let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
                  var item = activeDownloads[downloadId] else {
                print("Error: Finished HLS download task \(taskIdentifier) not found.")
                // NOTE: AVFoundation might manage cleanup, but log this.
                return
            }

            item.status = .completed
            item.progress = 1.0
            // IMPORTANT: location URL for HLS is often a reference, not a direct playable file path.
            // Store it, but playing it back might require AVURLAsset with this URL.
            item.completedFileURL = location
            item.downloadTaskIdentifier = nil // Clear task ID
            item.errorDescription = nil // Clear error

            // Update state
            activeDownloads.removeValue(forKey: downloadId)
            completedDownloads.append(item)
            saveCompletedDownloads()
            updateDownloadViewsOnMainThread() // Update UI

            print("HLS Download finished for \(item.title). Asset location: \(location)")
            sendNotification(title: "Download Complete", body: "\(item.title) has finished downloading.")
             NotificationCenter.default.post(name: .downloadCompleted, object: nil, userInfo: ["id": item.id, "title": item.title])
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {

         guard let taskIdentifier = assetDownloadTask.taskIdentifier as Int? else { return }

        // Update on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let downloadId = self.activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
                  var item = self.activeDownloads[downloadId] else {
                return
            }

            // Only update if the status is still downloading or pending
            guard item.status == .downloading || item.status == .pending else { return }

            var percentComplete: Float = 0.0
            let totalExpectedDuration = timeRangeExpectedToLoad.duration.seconds
            if totalExpectedDuration.isFinite && totalExpectedDuration > 0 {
                 var totalDurationLoaded: Double = 0
                for value in totalTimeRangesLoaded {
                    let loadedTimeRange = value.timeRangeValue
                    totalDurationLoaded += loadedTimeRange.duration.seconds
                }
                // Clamp progress between 0 and 1
                percentComplete = Float(min(max(0.0, totalDurationLoaded / totalExpectedDuration), 1.0))
            } else {
                // Handle indeterminate state if total duration isn't known yet
                print("HLS progress: Total duration not yet known for task \(taskIdentifier)")
                // Optionally set a specific state or keep progress at 0
            }

            item.progress = percentComplete
            item.status = .downloading // Ensure status is downloading
            // totalBytesExpected/Written might not be directly applicable for HLS duration-based progress
            item.totalBytesExpected = Int64(totalExpectedDuration * 1_000_000) // Example conversion if needed
            item.totalBytesWritten = Int64(item.progress * Float(item.totalBytesExpected ?? 0))

            // Update dictionary
            self.activeDownloads[downloadId] = item
            // self.updateDownloadViewsOnMainThread() // Consider throttling
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didResolve resolvedMediaSelection: AVMediaSelection) {
        print("HLS media selection resolved for task \(assetDownloadTask.taskIdentifier)")
    }
}

// MARK: - URLSessionTaskDelegate (Common error handling)
extension DownloadManager: URLSessionTaskDelegate {

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
         guard let taskIdentifier = task.taskIdentifier as Int? else {
            if error != nil {
                print("Error for untracked task: \(error!.localizedDescription)")
            }
            return
         }

        // Perform find and update on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

             // Find the item based on the task identifier *currently* associated with it
             guard let downloadId = self.activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
                  var currentItem = self.activeDownloads[downloadId] else {
                // If not found in active, it might have been completed successfully by didFinishDownloadingTo,
                // or cancelled previously. Log if there's an unexpected error.
                if error != nil && (error! as NSError).code != NSURLErrorCancelled {
                    print("Error reported for task \(taskIdentifier) which is not in the active download list (might be completed or already cancelled): \(error!.localizedDescription)")
                }
                return
            }

            // --- Start of Modified Logic ---
            currentItem.downloadTaskIdentifier = nil // Clear task ID regardless of outcome

            if let error = error {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                     // Item was cancelled, remove from active list
                     print("Task \(taskIdentifier) (\(currentItem.title)) was cancelled.")
                     self.activeDownloads.removeValue(forKey: downloadId)
                } else {
                    // Genuine failure
                    currentItem.status = .failed
                    currentItem.errorDescription = error.localizedDescription
                    print("Task \(taskIdentifier) (\(currentItem.title)) failed: \(error.localizedDescription)")
                    self.sendNotification(title: "Download Failed", body: "Failed to download \(currentItem.title): \(error.localizedDescription)")
                    // Update the item in the dictionary with the failed state
                    self.activeDownloads[downloadId] = currentItem
                     NotificationCenter.default.post(name: Notification.Name("DownloadFailedNotification"), object: self, userInfo: ["id": currentItem.id])
                }
            } else {
                 if currentItem.status != .completed {
                     print("Warning: Task \(taskIdentifier) (\(currentItem.title)) completed successfully (error == nil), but its state is still \(currentItem.status). Waiting for didFinishDownloadingTo delegate.")
                 }
            }
             self.updateDownloadViewsOnMainThread() // Update UI after potential state change or removal
        }
    }
}

// MARK: - URLSessionDelegate (For background session events)
extension DownloadManager: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            // Safely call the completion handler if it exists
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil // Reset handler
            print("Finished all events for background session: \(session.configuration.identifier ?? "N/A")")
        }
    }
}
