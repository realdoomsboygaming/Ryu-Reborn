//
//  DownloadManager.swift
//  Ryu
//
//  Created by Francesco on 17/07/24.
//

import UIKit
import Foundation
import Combine

// Download states
enum DownloadState: String, Codable {
    case queued
    case downloading(progress: Float, speed: Double)
    case paused
    case completed
    case failed(error: String)
    case cancelled
    
    var progress: Float {
        switch self {
        case .downloading(let progress, _): return progress
        default: return 0
        }
    }
    
    var speed: Double {
        switch self {
        case .downloading(_, let speed): return speed
        default: return 0
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "queued": self = .queued
        case "downloading": self = .downloading(progress: 0, speed: 0)
        case "paused": self = .paused
        case "completed": self = .completed
        case "failed": self = .failed(error: "Unknown error")
        case "cancelled": self = .cancelled
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid state")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .queued: try container.encode("queued")
        case .downloading: try container.encode("downloading")
        case .paused: try container.encode("paused")
        case .completed: try container.encode("completed")
        case .failed: try container.encode("failed")
        case .cancelled: try container.encode("cancelled")
        }
    }
}

// Download priority
enum DownloadPriority: Int, Codable {
    case low = 0
    case normal = 1
    case high = 2
}

// Download metadata
struct DownloadMetadata: Codable {
    let id: String
    let title: String
    let sourceURL: URL
    let destinationURL: URL
    let fileSize: Int64?
    let createdAt: Date
    let priority: DownloadPriority
    var state: DownloadState
    var error: String?
    var resumeData: Data?
}

class DownloadManager {
    static let shared = DownloadManager()
    
    private let queue = OperationQueue()
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private var activeDownloads: [String: DownloadMetadata] = [:]
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var downloadProgress: [String: (progress: Float, speed: Int64)] = [:]
    private var lastProgressUpdate: [String: Date] = [:]
    private var lastBytesDownloaded: [String: Int64] = [:]
    
    private init() {
        queue.maxConcurrentOperationCount = 3
        loadSavedDownloads()
    }
    
    // MARK: - Public Methods
    
    func startDownload(url: URL, title: String) -> String {
        let id = UUID().uuidString
        let metadata = DownloadMetadata(
            id: id,
            title: title,
            sourceURL: url,
            destinationURL: URL(fileURLWithPath: ""),
            fileSize: nil,
            createdAt: Date(),
            priority: .normal,
            state: .queued
        )
        
        activeDownloads[id] = metadata
        saveDownloads()
        
        let task = createDownloadTask(for: metadata)
        downloadTasks[id] = task
        task.resume()
        
        return id
    }
    
    func pauseDownload(id: String) {
        guard let task = downloadTasks[id] else { return }
        task.suspend()
        
        if var metadata = activeDownloads[id] {
            metadata.state = .paused
            activeDownloads[id] = metadata
            saveDownloads()
            postNotification(name: .downloadDidUpdate, metadata: metadata)
        }
    }
    
    func resumeDownload(id: String) {
        guard let task = downloadTasks[id] else { return }
        task.resume()
        
        if var metadata = activeDownloads[id] {
            metadata.state = .downloading(progress: metadata.progress, speed: 0)
            activeDownloads[id] = metadata
            saveDownloads()
            postNotification(name: .downloadDidUpdate, metadata: metadata)
        }
    }
    
    func cancelDownload(id: String) {
        guard let task = downloadTasks[id] else { return }
        task.cancel()
        
        downloadTasks.removeValue(forKey: id)
        downloadProgress.removeValue(forKey: id)
        lastProgressUpdate.removeValue(forKey: id)
        lastBytesDownloaded.removeValue(forKey: id)
        
        if var metadata = activeDownloads[id] {
            metadata.state = .cancelled
            activeDownloads[id] = metadata
            saveDownloads()
            postNotification(name: .downloadDidUpdate, metadata: metadata)
        }
    }
    
    func getActiveDownloads() -> [DownloadMetadata] {
        return Array(activeDownloads.values)
    }
    
    func getDownloadMetadata(id: String) -> DownloadMetadata? {
        return activeDownloads[id]
    }
    
    // MARK: - Private Methods
    
    private func createDownloadTask(for metadata: DownloadMetadata) -> URLSessionDownloadTask {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: metadata.sourceURL)
        
        task.taskDescription = metadata.id
        return task
    }
    
    private func loadSavedDownloads() {
        guard let data = UserDefaults.standard.data(forKey: "savedDownloads"),
              let downloads = try? decoder.decode([String: DownloadMetadata].self, from: data) else {
            return
        }
        
        activeDownloads = downloads
    }
    
    private func saveDownloads() {
        guard let data = try? encoder.encode(activeDownloads) else { return }
        UserDefaults.standard.set(data, forKey: "savedDownloads")
    }
    
    private func postNotification(name: Notification.Name, metadata: DownloadMetadata) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["metadata": metadata])
    }
    
    private func calculateDownloadSpeed(for id: String) -> Int64 {
        guard let lastUpdate = lastProgressUpdate[id],
              let lastBytes = lastBytesDownloaded[id] else {
            return 0
        }
        
        let timeInterval = Date().timeIntervalSince(lastUpdate)
        guard timeInterval > 0 else { return 0 }
        
        let currentBytes = Int64(Float(lastBytes) * (activeDownloads[id]?.progress ?? 0))
        let bytesPerSecond = Double(currentBytes - lastBytes) / timeInterval
        
        return Int64(bytesPerSecond)
    }
    
    private func updateDownloadProgress(id: String, progress: Float) {
        let speed = calculateDownloadSpeed(for: id)
        downloadProgress[id] = (progress: progress, speed: speed)
        lastProgressUpdate[id] = Date()
        
        if var metadata = activeDownloads[id] {
            metadata.state = .downloading(progress: progress, speed: speed)
            activeDownloads[id] = metadata
            saveDownloads()
            postNotification(name: .downloadDidUpdate, metadata: metadata)
        }
    }
    
    private func handleDownloadCompletion(id: String, location: URL) {
        guard var metadata = activeDownloads[id] else { return }
        
        do {
            let destinationURL = try getDestinationURL(for: metadata)
            try fileManager.moveItem(at: location, to: destinationURL)
            
            metadata.state = .completed
            activeDownloads[id] = metadata
            saveDownloads()
            
            downloadTasks.removeValue(forKey: id)
            downloadProgress.removeValue(forKey: id)
            lastProgressUpdate.removeValue(forKey: id)
            lastBytesDownloaded.removeValue(forKey: id)
            
            postNotification(name: .downloadDidComplete, metadata: metadata)
        } catch {
            metadata.state = .failed(error: error.localizedDescription)
            activeDownloads[id] = metadata
            saveDownloads()
            postNotification(name: .downloadDidUpdate, metadata: metadata)
        }
    }
    
    private func getDestinationURL(for metadata: DownloadMetadata) throws -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = metadata.sourceURL.lastPathComponent
        return documentsPath.appendingPathComponent(fileName)
    }
}

// MARK: - URLSession Delegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        handleDownloadCompletion(id: id, location: location)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        lastBytesDownloaded[id] = totalBytesWritten
        updateDownloadProgress(id: id, progress: progress)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let downloadDidUpdate = Notification.Name("downloadDidUpdate")
    static let downloadDidComplete = Notification.Name("downloadDidComplete")
}


