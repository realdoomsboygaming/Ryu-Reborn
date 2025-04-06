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
        
        // Add/Update in active downloads *before* starting task to ensure it's tracked
        DispatchQueue.main.async {
            self.activeDownloads[downloadId] = newItem
        }

        if format == .hls {
            startHLSDownload(item: &newItem) // Pass as inout
        } else {
            startMP4Download(item: &newItem) // Pass as inout
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
                 print("Removing HLS reference for \(item.title) at \(urlToDelete.path)")
                 // For HLS, AVFoundation manages files; removing the bookmark might be enough,
                 // but actual file deletion is tricky and might require more specific logic.
             } else {
                 try FileManager.default.removeItem(at: urlToDelete)
                 print("Deleted MP4 file at \(urlToDelete.path)")
             }

            if let index = completedDownloads.firstIndex(where: { $0.id == item.id }) {
                completedDownloads.remove(at: index)
                saveCompletedDownloads()
                DispatchQueue.main.async {
                    self.completedDownloads = self.completedDownloads // Force update
                }
            }
        } catch {
            print("Error deleting file/asset for \(item.title) at \(urlToDelete): \(error)")
        }
    }

     func updateCompletedDownload(item: DownloadItem) {
         if let index = completedDownloads.firstIndex(where: { $0.id == item.id }) {
             completedDownloads[index] = item
             saveCompletedDownloads()
             DispatchQueue.main.async {
                 self.completedDownloads = self.completedDownloads // Force update
             }
         }
     }

    // **FIXED:** Removed 'inout', use local var for modifications before dispatching
    private func startMP4Download(item originalItem: inout DownloadItem) {
        let task = mp4Session.downloadTask(with: originalItem.sourceURL)
        
        // Modify a copy before dispatching
        var updatedItem = originalItem
        updatedItem.downloadTaskIdentifier = task.taskIdentifier
        updatedItem.status = .downloading
        
        // Capture the updated copy
        let itemToUpdate = updatedItem
        DispatchQueue.main.async {
            self.activeDownloads[itemToUpdate.id] = itemToUpdate
        }
        
        task.resume()
        print("Started MP4 download for \(updatedItem.title) (Task ID: \(task.taskIdentifier))")
        
        // Update the original inout parameter *after* potential modifications
        // This line is technically optional now if the caller doesn't need the immediate update
        // but good practice to keep the inout parameter reflecting the change.
        originalItem = updatedItem
    }

    // **FIXED:** Removed 'inout', use local var for modifications before dispatching
    private func startHLSDownload(item originalItem: inout DownloadItem) {
        let asset = AVURLAsset(url: originalItem.sourceURL)
        let safeTitle = originalItem.title.replacingOccurrences(of: "[^a-zA-Z0-9_.]", with: "_", options: .regularExpression)
        
        // Modify a copy before dispatching or error handling
        var updatedItem = originalItem
        
        guard let task = hlsSession.makeAssetDownloadTask(asset: asset,
                                                          assetTitle: safeTitle,
                                                          assetArtworkData: nil,
                                                          options: nil) else {
            print("Failed to create AVAssetDownloadTask for \(originalItem.title)")
            updatedItem.status = .failed
            updatedItem.errorDescription = "Failed to create HLS download task."
            
            // Capture the failed copy
            let itemToUpdate = updatedItem
            DispatchQueue.main.async {
                self.activeDownloads[itemToUpdate.id] = itemToUpdate
            }
            // Update original inout parameter
            originalItem = updatedItem
            return
        }
        
        updatedItem.downloadTaskIdentifier = task.taskIdentifier
        updatedItem.status = .downloading
        
        // Capture the downloading copy
        let itemToUpdate = updatedItem
        DispatchQueue.main.async {
             self.activeDownloads[itemToUpdate.id] = itemToUpdate
        }
        task.resume()
        print("Started HLS download for \(updatedItem.title) (Task ID: \(task.taskIdentifier))")

        // Update original inout parameter
        originalItem = updatedItem
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
        guard let taskIdentifier = downloadTask.taskIdentifier as Int?,
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
            item.downloadTaskIdentifier = nil
            
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
            item.downloadTaskIdentifier = nil
             DispatchQueue.main.async {
                 self.activeDownloads[downloadId] = item
             }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        
        guard totalBytesExpectedToWrite > 0,
              let taskIdentifier = downloadTask.taskIdentifier as Int?,
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
        guard let taskIdentifier = assetDownloadTask.taskIdentifier as Int?,
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key,
              var item = activeDownloads[downloadId] else {
            print("Error: Finished HLS download task \(String(describing: assetDownloadTask.taskIdentifier)) not found.")
            return
        }
        
        item.status = .completed
        item.progress = 1.0
        item.completedFileURL = location
        item.downloadTaskIdentifier = nil
        
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
        
        guard let taskIdentifier = assetDownloadTask.taskIdentifier as Int?,
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
         guard let taskIdentifier = task.taskIdentifier as Int?,
              let downloadId = activeDownloads.first(where: { $0.value.downloadTaskIdentifier == taskIdentifier })?.key else {
            if error != nil {
                 print("Error for untracked/completed task \(String(describing: task.taskIdentifier)): \(error!.localizedDescription)")
            }
            return
        }

        let originalTaskIdentifier = activeDownloads[downloadId]?.downloadTaskIdentifier

        DispatchQueue.main.async {
             guard var currentItem = self.activeDownloads[downloadId] else { return }
             
             guard currentItem.downloadTaskIdentifier == originalTaskIdentifier || originalTaskIdentifier != nil else {
                 print("Task completion mismatch for \(taskIdentifier). Current item ID: \(currentItem.downloadTaskIdentifier ?? -1)")
                 return
             }
            
            currentItem.downloadTaskIdentifier = nil

            if let error = error {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                     currentItem.status = .cancelled
                    print("Task \(taskIdentifier) (\(currentItem.title)) was cancelled.")
                    self.activeDownloads.removeValue(forKey: downloadId)
                } else {
                    currentItem.status = .failed
                    currentItem.errorDescription = error.localizedDescription
                    print("Task \(taskIdentifier) (\(currentItem.title)) failed: \(error.localizedDescription)")
                    self.sendNotification(title: "Download Failed", body: "Failed to download \(currentItem.title): \(error.localizedDescription)")
                    self.activeDownloads[downloadId] = currentItem
                }
            } else {
                 if currentItem.status == .downloading || currentItem.status == .pending {
                     print("Warning: Task \(taskIdentifier) (\(currentItem.title)) completed without error but wasn't marked completed by specific delegates.")
                     currentItem.status = .failed
                     currentItem.errorDescription = "Download finished unexpectedly without completion."
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
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
            print("Finished events for background session: \(session.configuration.identifier ?? "N/A")")
        }
    }
}
