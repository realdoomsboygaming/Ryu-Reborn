import Foundation
import AVFoundation
import Combine
import UserNotifications

// Define DownloadItem struct within the same file scope for clarity
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
        hlsSession = AVAssetDownloadURLSession(configuration: hlsConfig, assetDownloadDelegate: self, delegateQueue: nil)

        loadCompletedDownloads()
        restoreActiveDownloads()
        requestNotificationPermission()
    }

    func startDownload(url: URL, title: String) {
        let downloadId = url.absoluteString
        
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
            format = .mp4
        }

        var newItem = DownloadItem(id: downloadId, title: title, sourceURL: url, format: format)
        newItem.status = .pending
        
        DispatchQueue.main.async {
            self.activeDownloads[downloadId] = newItem
        }

        if format == .hls {
            startHLSDownload(item: &newItem)
        } else {
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
            self.activeDownloads.removeValue(forKey: downloadId)
        }
        print("Cancelled download for \(item.title)")
    }

    func getActiveDownloadItems() -> [DownloadItem] {
        return Array(activeDownloads.values).sorted { $0.title < $1.title }
    }
    
    func getCompletedDownloadItems() -> [DownloadItem] {
        return completedDownloads.sorted { ($0.completedFileURL?.path ?? "") < ($1.completedFileURL?.path ?? "") }
    }
    
    func deleteCompletedDownload(item: DownloadItem) {
        guard let urlToDelete = item.completedFileURL else {
            print("Error: No file URL for completed download \(item.title)")
            return
        }
        
        do {
             if item.format == .hls {
                 // Deleting HLS assets is managed by AVFoundation; attempt removal if needed,
                 // but the primary action is removing the bookmark/reference.
                 // If 'location' stored is a bookmark, try resolving and removing actual files if possible,
                 // otherwise, just remove the reference. For simplicity, we just remove the reference.
                 print("Removing HLS reference for \(item.title) at \(urlToDelete.path)")
             } else {
                 try FileManager.default.removeItem(at: urlToDelete)
                 print("Deleted MP4 file at \(urlToDelete.path)")
             }

            if let index = completedDownloads.firstIndex(where: { $0.id == item.id }) {
                completedDownloads.remove(at: index)
                saveCompletedDownloads()
                DispatchQueue.main.async {
                    // Force update published property
                     self.completedDownloads = self.completedDownloads
                }
            }
        } catch {
            print("Error deleting file/asset for \(item.title) at \(urlToDelete): \(error)")
        }
    }

    // Method to update a completed download item (e.g., after renaming)
     func updateCompletedDownload(item: DownloadItem) {
         if let index = completedDownloads.firstIndex(where: { $0.id == item.id }) {
             completedDownloads[index] = item
             saveCompletedDownloads()
             DispatchQueue.main.async {
                  // Force update published property
                 self.completedDownloads = self.completedDownloads
             }
         }
     }


    private func startMP4Download(item: inout DownloadItem) {
        let task = mp4Session.downloadTask(with: item.sourceURL)
        item.downloadTaskIdentifier = task.taskIdentifier
        item.status = .downloading
        
        DispatchQueue.main.async {
            self.activeDownloads[item.id] = item
        }
        task.resume()
        print("Started MP4 download for \(item.title) (Task ID: \(task.taskIdentifier))")
    }

    private func startHLSDownload(item: inout DownloadItem) {
        let asset = AVURLAsset(url: item.sourceURL)
        let safeTitle = item.title.replacingOccurrences(of: "[^a-zA-Z0-9_.]", with: "_", options: .regularExpression)
        
        guard let task = hlsSession.makeAssetDownloadTask(asset: asset,
                                                          assetTitle: safeTitle,
                                                          assetArtworkData: nil,
                                                          options: nil) else {
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
             self.activeDownloads[item.id] = item
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
        } else {
            print("Error loading completed downloads: Decoding failed.")
            try? FileManager.default.removeItem(at: completedDownloadsURL())
        }
    }
    
    private func restoreActiveDownloads() {
       mp4Session.getAllTasks { tasks in
           print("Found \(tasks.count) MP4 background tasks.")
       }
       hlsSession.getAllTasks { tasks in
           print("Found \(tasks.count) HLS background tasks.")
       }
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
    
    private func getUniqueFileURL(for fileName: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var finalURL = directory.appendingPathComponent(fileName)
        var counter = 1
        
         do {
             try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
         } catch {
             print("Error creating documents directory: \(error)")
         }

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
        guard let taskIdentifier = downloadTask.taskIdentifier as Int?, // Use direct taskIdentifier
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
              var item = activeDownloads[downloadId] else {
            print("Error: Finished download task \(String(describing: downloadTask.taskIdentifier)) not found in active downloads.")
            try? FileManager.default.removeItem(at: location)
            return
        }

        let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let originalFileName = downloadTask.originalRequest?.url?.lastPathComponent ?? "\(item.title).mp4"
        let safeFileName = originalFileName.replacingOccurrences(of: "[^a-zA-Z0-9_.]", with: "_", options: .regularExpression)
        let destinationURL = getUniqueFileURL(for: safeFileName, in: documentsDirectoryURL)

        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            print("MP4 File moved to: \(destinationURL.path)")

            item.status = .completed
            item.progress = 1.0
            item.completedFileURL = destinationURL
            item.downloadTaskIdentifier = nil // Correct assignment
            
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: downloadId)
                self.completedDownloads.append(item)
                self.saveCompletedDownloads()
                 self.completedDownloads = self.completedDownloads
            }

            sendNotification(title: "Download Complete", body: "\(item.title) has finished downloading.")
            NotificationCenter.default.post(name: .downloadCompleted, object: nil, userInfo: ["title": item.title])

        } catch {
            print("Error moving MP4 file for \(item.title): \(error)")
            item.status = .failed
            item.errorDescription = error.localizedDescription
            item.downloadTaskIdentifier = nil // Correct assignment
             DispatchQueue.main.async {
                 self.activeDownloads[downloadId] = item
             }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        
        guard totalBytesExpectedToWrite > 0,
              let taskIdentifier = downloadTask.taskIdentifier as Int?, // Use direct taskIdentifier
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
              var item = activeDownloads[downloadId] else {
                  return
              }

        item.progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        item.totalBytesWritten = totalBytesWritten
        item.totalBytesExpected = totalBytesExpectedToWrite
        item.status = .downloading
        
        DispatchQueue.main.async {
             if self.activeDownloads[downloadId] != nil {
                 self.activeDownloads[downloadId] = item
             }
        }
    }
}

// MARK: - AVAssetDownloadDelegate (for HLS)
extension DownloadManager: AVAssetDownloadDelegate {
    
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskIdentifier = assetDownloadTask.taskIdentifier as Int?, // Use direct taskIdentifier
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
              var item = activeDownloads[downloadId] else {
            print("Error: Finished HLS download task \(String(describing: assetDownloadTask.taskIdentifier)) not found.")
            return
        }
        
        item.status = .completed
        item.progress = 1.0
        item.completedFileURL = location
        item.downloadTaskIdentifier = nil // Correct assignment
        
        DispatchQueue.main.async {
            self.activeDownloads.removeValue(forKey: downloadId)
            self.completedDownloads.append(item)
            self.saveCompletedDownloads()
             self.completedDownloads = self.completedDownloads
        }

        print("HLS Download finished for \(item.title). Asset location: \(location)")
        sendNotification(title: "Download Complete", body: "\(item.title) has finished downloading.")
        NotificationCenter.default.post(name: .downloadCompleted, object: nil, userInfo: ["title": item.title])
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        
        guard let taskIdentifier = assetDownloadTask.taskIdentifier as Int?, // Use direct taskIdentifier
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
              var item = activeDownloads[downloadId] else { return }
              
        var percentComplete: Float = 0.0
        if timeRangeExpectedToLoad.duration.seconds > 0 {
             var totalDurationLoaded: Double = 0
            for value in totalTimeRangesLoaded {
                let loadedTimeRange = value.timeRangeValue
                totalDurationLoaded += loadedTimeRange.duration.seconds
            }
            percentComplete = Float(min(max(0.0, totalDurationLoaded / timeRangeExpectedToLoad.duration.seconds), 1.0))
        }

        item.progress = percentComplete
        item.status = .downloading
        
        DispatchQueue.main.async {
             if self.activeDownloads[downloadId] != nil {
                 self.activeDownloads[downloadId] = item
             }
        }
    }
    
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didResolve resolvedMediaSelection: AVMediaSelection) {
        print("HLS media selection resolved for task \(assetDownloadTask.taskIdentifier)")
    }
}


// MARK: - URLSessionTaskDelegate (Common error handling)
extension DownloadManager: URLSessionTaskDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
         guard let taskIdentifier = task.taskIdentifier as Int?, // Use direct taskIdentifier
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key else {
            // Task not actively tracked or already completed/cancelled
            if error != nil {
                 print("Error for untracked/completed task \(String(describing: task.taskIdentifier)): \(error!.localizedDescription)")
            }
            return
        }

        // Fetch item again inside dispatch block for thread safety
        DispatchQueue.main.async {
            guard var item = self.activeDownloads[downloadId] else { return }

            // Ensure this completion matches the stored identifier, in case of task reuse (less likely with background)
             guard item.downloadTaskIdentifier == taskIdentifier else {
                 print("Task completion mismatch for \(taskIdentifier). Current item ID: \(item.downloadTaskIdentifier ?? -1)")
                 return
             }
            
            item.downloadTaskIdentifier = nil // Clear ID as task is finishing

            if let error = error {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                     item.status = .cancelled
                    print("Task \(taskIdentifier) (\(item.title)) was cancelled.")
                    self.activeDownloads.removeValue(forKey: downloadId) // Remove cancelled
                } else {
                    item.status = .failed
                    item.errorDescription = error.localizedDescription
                    print("Task \(taskIdentifier) (\(item.title)) failed: \(error.localizedDescription)")
                    self.sendNotification(title: "Download Failed", body: "Failed to download \(item.title): \(error.localizedDescription)")
                    self.activeDownloads[downloadId] = item // Keep failed item in active list
                }
            } else {
                 // If no error, success is handled by specific delegates. Check if status wasn't updated.
                 if item.status == .downloading || item.status == .pending {
                     print("Warning: Task \(taskIdentifier) (\(item.title)) completed without error but wasn't marked completed.")
                     item.status = .failed // Treat as failure if not marked completed
                     item.errorDescription = "Download finished unexpectedly without completion."
                     self.activeDownloads[downloadId] = item
                     self.sendNotification(title: "Download Failed", body: "\(item.title) finished unexpectedly.")
                 }
             }
        }
    }
}

// MARK: - URLSessionDelegate (For background session events)
extension DownloadManager: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
            print("Finished events for background session: \(session.configuration.identifier ?? "N/A")")
        }
    }
}
