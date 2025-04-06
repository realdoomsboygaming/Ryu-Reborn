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
    case downloading
    case paused
    case completed
    case failed
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
        case "failed": self = .failed
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
    
    private var activeDownloads: [String: DownloadMetadata] = [:]
    private var downloadQueue: OperationQueue
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var stateObservers: [String: AnyCancellable] = [:]
    
    private let fileManager = FileManager.default
    private let metadataQueue = DispatchQueue(label: "com.ryu.downloadmanager.metadata")
    private let downloadDirectory: URL
    
    private init() {
        downloadQueue = OperationQueue()
        downloadQueue.maxConcurrentOperationCount = 3
        downloadQueue.qualityOfService = .utility
        
        // Set up downloads directory
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        downloadDirectory = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create downloads directory: \(error)")
        }
        
        // Load existing downloads
        loadExistingDownloads()
    }
    
    // MARK: - Public Methods
    
    func startDownload(url: URL, title: String, priority: DownloadPriority = .normal, progress: @escaping (Float) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        let downloadId = UUID().uuidString
        let sanitizedTitle = title.sanitizedFileName
        let destinationURL = downloadDirectory.appendingPathComponent("\(sanitizedTitle).mp4")
        
        let metadata = DownloadMetadata(
            id: downloadId,
            title: title,
            sourceURL: url,
            destinationURL: destinationURL,
            fileSize: nil,
            createdAt: Date(),
            priority: priority,
            state: .queued
        )
        
        metadataQueue.async { [weak self] in
            self?.activeDownloads[downloadId] = metadata
            self?.saveMetadata()
        }
        
        setupDownloadTask(for: metadata, progress: progress, completion: completion)
    }
    
    func pauseDownload(id: String) {
        guard let task = downloadTasks[id] else { return }
        task.suspend()
        
        metadataQueue.async { [weak self] in
            guard let self = self,
                  var metadata = self.activeDownloads[id] else { return }
            metadata.state = .paused
            metadata.resumeData = task.resumeData
            self.activeDownloads[id] = metadata
            self.saveMetadata()
        }
    }
    
    func resumeDownload(id: String) {
        guard let metadata = activeDownloads[id],
              let resumeData = metadata.resumeData else { return }
        
        let configuration = URLSessionConfiguration.background(withIdentifier: "me.cranci.downloader.\(id)")
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration, delegate: BackgroundSessionDelegate.shared, delegateQueue: nil)
        
        let task = session.downloadTask(withResumeData: resumeData)
        downloadTasks[id] = task
        
        metadataQueue.async { [weak self] in
            guard let self = self else { return }
            var updatedMetadata = metadata
            updatedMetadata.state = .downloading(progress: 0, speed: 0)
            self.activeDownloads[id] = updatedMetadata
            self.saveMetadata()
        }
        
        task.resume()
    }
    
    func cancelDownload(id: String) {
        guard let task = downloadTasks[id] else { return }
        task.cancel()
        downloadTasks.removeValue(forKey: id)
        
        metadataQueue.async { [weak self] in
            guard let self = self else { return }
            var metadata = self.activeDownloads[id]
            metadata?.state = .cancelled
            self.activeDownloads[id] = metadata
            self.saveMetadata()
        }
    }
    
    func getActiveDownloads() -> [String: DownloadMetadata] {
        return activeDownloads
    }
    
    // MARK: - Private Methods
    
    private func setupDownloadTask(for metadata: DownloadMetadata, progress: @escaping (Float) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        let configuration = URLSessionConfiguration.background(withIdentifier: "me.cranci.downloader.\(metadata.id)")
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration, delegate: BackgroundSessionDelegate.shared, delegateQueue: nil)
        
        var request = URLRequest(url: metadata.sourceURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        let task = session.downloadTask(with: request)
        downloadTasks[metadata.id] = task
        
        // Set up progress observation
        let progressObserver = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] taskProgress, _ in
            DispatchQueue.main.async {
                let speed = self?.calculateDownloadSpeed(for: metadata.id) ?? 0
                progress(Float(taskProgress.fractionCompleted))
                
                self?.metadataQueue.async {
                    guard let self = self else { return }
                    var updatedMetadata = self.activeDownloads[metadata.id]
                    updatedMetadata?.state = .downloading(progress: Float(taskProgress.fractionCompleted), speed: speed)
                    self.activeDownloads[metadata.id] = updatedMetadata
                    self.saveMetadata()
                }
            }
        }
        
        stateObservers[metadata.id] = progressObserver
        
        // Set up completion handler
        BackgroundSessionDelegate.shared.downloadCompletionHandler = { [weak self] result in
            DispatchQueue.main.async {
                self?.downloadTasks.removeValue(forKey: metadata.id)
                self?.stateObservers.removeValue(forKey: metadata.id)
                
                self?.metadataQueue.async {
                    guard let self = self else { return }
                    var updatedMetadata = self.activeDownloads[metadata.id]
                    switch result {
                    case .success(let url):
                        updatedMetadata?.state = .completed
                        completion(.success(url))
                    case .failure(let error):
                        updatedMetadata?.state = .failed
                        updatedMetadata?.error = error.localizedDescription
                        completion(.failure(error))
                    }
                    self.activeDownloads[metadata.id] = updatedMetadata
                    self.saveMetadata()
                }
            }
        }
        
        task.resume()
    }
    
    private func calculateDownloadSpeed(for id: String) -> Double {
        // Implement download speed calculation
        return 0.0
    }
    
    private func loadExistingDownloads() {
        let metadataURL = downloadDirectory.appendingPathComponent("downloads.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let downloads = try? JSONDecoder().decode([String: DownloadMetadata].self, from: data) else {
            return
        }
        
        activeDownloads = downloads
    }
    
    private func saveMetadata() {
        let metadataURL = downloadDirectory.appendingPathComponent("downloads.json")
        guard let data = try? JSONEncoder().encode(activeDownloads) else { return }
        
        do {
            try data.write(to: metadataURL)
        } catch {
            print("Failed to save download metadata: \(error)")
        }
    }
}

// MARK: - Helper Extensions

extension String {
    var sanitizedFileName: String {
        return self.replacingOccurrences(of: "[\\/:*?\"<>|]", with: "_", options: .regularExpression)
    }
}
