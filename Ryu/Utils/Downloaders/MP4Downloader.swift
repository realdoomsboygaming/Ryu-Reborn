//
//  MP4Downloader.swift
//  Ryu
//
//  Created by Francesco on 17/07/24.
//

import UIKit
import Foundation
import UserNotifications

class MP4Downloader {
    static var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    static func requestNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error.localizedDescription)")
            } else if !granted {
                print("Notification authorization not granted")
            }
        }
    }
    
    static func handleDownloadResult(_ result: Result<URL, Error>) {
        let content = UNMutableNotificationContent()
        switch result {
        case .success:
            content.title = "Download Complete"
            content.body = "Your Episode download has completed, you can now start watching it!"
            content.sound = .default
        case .failure(let error):
            content.title = "Download Failed"
            content.body = "There was an error downloading the episode: \(error.localizedDescription)"
            content.sound = .defaultCritical
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error adding notification: \(error.localizedDescription)")
            }
        }
    }
    
    static func getUniqueFileURL(for fileName: String, in directory: URL) -> URL {
        let fileURL = URL(fileURLWithPath: fileName)
        let fileNameWithoutExtension = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension
        var newFileName = fileName
        var counter = 1
        
        var uniqueFileURL = directory.appendingPathComponent(newFileName)
        while FileManager.default.fileExists(atPath: uniqueFileURL.path) {
            counter += 1
            newFileName = "\(fileNameWithoutExtension)-\(counter).\(fileExtension)"
            uniqueFileURL = directory.appendingPathComponent(newFileName)
        }
        
        return uniqueFileURL
    }
}

class BackgroundSessionDelegate: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    static let shared = BackgroundSessionDelegate()
    var downloadCompletionHandler: ((Result<URL, Error>) -> Void)?
    
    private var downloadProgress: [String: (bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)] = [:]
    private let progressQueue = DispatchQueue(label: "com.ryu.downloadmanager.progress")
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        if let error = error {
            print("Session became invalid: \(error.localizedDescription)")
            if let taskId = session.configuration.identifier?.replacingOccurrences(of: "me.cranci.downloader.", with: "") {
                downloadCompletionHandler?(.failure(error))
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskId = session.configuration.identifier?.replacingOccurrences(of: "me.cranci.downloader.", with: "") else {
            downloadCompletionHandler?(.failure(NSError(domain: "DownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid download task"])))
            return
        }
        
        do {
            // Create destination directory if it doesn't exist
            try FileManager.default.createDirectory(at: metadata.destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: metadata.destinationURL.path) {
                try FileManager.default.removeItem(at: metadata.destinationURL)
            }
            
            // Move downloaded file to destination
            try FileManager.default.moveItem(at: location, to: metadata.destinationURL)
            
            // Update file size in metadata
            let attributes = try FileManager.default.attributesOfItem(atPath: metadata.destinationURL.path)
            let fileSize = attributes[.size] as? Int64
            
            downloadCompletionHandler?(.success(metadata.destinationURL))
            
            // Post notification for download completion
            NotificationCenter.default.post(name: .downloadCompleted, object: nil, userInfo: [
                "id": taskId,
                "title": metadata.title,
                "url": metadata.destinationURL
            ])
            
        } catch {
            print("Error handling downloaded file: \(error.localizedDescription)")
            downloadCompletionHandler?(.failure(error))
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let taskId = session.configuration.identifier?.replacingOccurrences(of: "me.cranci.downloader.", with: "") else { return }
        
        progressQueue.async { [weak self] in
            self?.downloadProgress[taskId] = (bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Task completed with error: \(error.localizedDescription)")
            if let taskId = session.configuration.identifier?.replacingOccurrences(of: "me.cranci.downloader.", with: "") {
                downloadCompletionHandler?(.failure(error))
            }
        }
    }
    
    func getDownloadProgress(for taskId: String) -> (bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)? {
        var progress: (bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)?
        progressQueue.sync {
            progress = downloadProgress[taskId]
        }
        return progress
    }
}
