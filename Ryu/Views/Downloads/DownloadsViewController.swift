import UIKit
import AVKit
import AVFoundation

class DownloadListViewController: UIViewController {
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.backgroundColor = .systemGroupedBackground
        table.separatorStyle = .singleLine
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var downloads: [DownloadItem] = []
    private let downloadManager = DownloadManager.shared // Use the singleton
    private let refreshControl = UIRefreshControl()
    
    private let emptyMessages = [
        "Looks like a black hole has been here! No downloads found. Maybe they've been sucked into oblivion?",
        "Nothing to see here! All downloads have mysteriously vanished.",
        "The download list is emptier than space itself.",
        "No downloads available. Did Thanos snap them away?",
        "Oops, it's all gone! Like a magician's trick, the downloads disappeared!",
        "No downloads. Perhaps they're hiding from us?",
        "Looks like the downloads took a vacation. Check back later!",
        "Downloads? What downloads? It's all an illusion!",
        "Looks like the downloads decided to play hide and seek!",
        "No downloads available. It’s like they’ve gone off to a secret party.",
        "Nothing here. Maybe the downloads are waiting for a dramatic entrance."
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        
        setupTableView()
        setupEmptyStateLabel()
        loadDownloads()
        setupNavigationBar()
        setupRefreshControl()
        updateTitle()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleDownloadListUpdate), name: .downloadCompleted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDownloadListUpdate), name: .downloadListUpdated, object: nil)
    }
    
     deinit {
         NotificationCenter.default.removeObserver(self)
     }
     
     @objc private func handleDownloadListUpdate() {
         loadDownloads()
     }
    
    private func setupRefreshControl() {
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    @objc private func refreshData() {
        loadDownloads()
        refreshControl.endRefreshing()
    }
    
    private func setupNavigationBar() {
        let filesButton = UIBarButtonItem(image: UIImage(systemName: "folder"), style: .plain, target: self, action: #selector(openInFilesApp))
        navigationItem.rightBarButtonItem = filesButton
    }
    
    private func setupTableView() {
        view.addSubview(tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemBackground
        tableView.register(DownloadCell.self, forCellReuseIdentifier: "DownloadCell")
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupEmptyStateLabel() {
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32), // Adjusted constraints
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32) // Adjusted constraints
        ])
    }
    
    @objc private func openInFilesApp() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Unable to access Documents directory")
            return
        }
        
        if UIApplication.shared.canOpenURL(documentsURL) {
             UIApplication.shared.open(documentsURL, options: [:]) { success in
                 if !success {
                     print("Failed to open Files app directory")
                 }
             }
        } else {
            print("Cannot open Files app directory")
        }
    }
    
    private func loadDownloads() {
        downloads = downloadManager.getCompletedDownloadItems()
        
        tableView.reloadData()
        emptyStateLabel.isHidden = !downloads.isEmpty
        updateTitle()
        
        if downloads.isEmpty {
            emptyStateLabel.text = emptyMessages.randomElement()
        }
    }
    
    private func updateTitle() {
        let totalSize = calculateTotalDownloadSize()
        let formattedSize = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        title = "Downloaded - \(formattedSize)"
    }
    
    private func calculateTotalDownloadSize() -> Int64 {
        var totalSize: Int64 = 0
        for downloadItem in downloads {
             if downloadItem.format == .mp4, let fileURL = downloadItem.completedFileURL {
                 do {
                     let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                     totalSize += attributes[.size] as? Int64 ?? 0
                 } catch {
                     print("Error getting file size for \(downloadItem.title): \(error.localizedDescription)")
                 }
             } else if downloadItem.format == .hls {
                 totalSize += downloadItem.totalBytesExpected ?? 0
             }
        }
        return totalSize
    }
    
    private func playDownload(item: DownloadItem) {
         guard let contentURL = item.completedFileURL else {
             showAlert(title: "Error", message: "Download location not found.") // Use the helper
             return
         }

         let player: AVPlayer
         if item.format == .hls {
             let asset = AVURLAsset(url: contentURL)
             let playerItem = AVPlayerItem(asset: asset)
             player = AVPlayer(playerItem: playerItem)
             print("Playing HLS from asset location: \(contentURL)")
         } else {
             player = AVPlayer(url: contentURL)
             print("Playing MP4 from file: \(contentURL.path)")
         }

         let playerViewController = NormalPlayer()
         playerViewController.player = player

         present(playerViewController, animated: true) {
             player.play()
         }
     }

    private func deleteDownload(at indexPath: IndexPath) {
        let itemToDelete = downloads[indexPath.row]
        downloadManager.deleteCompletedDownload(item: itemToDelete)
        // The local 'downloads' array and table view will be updated by the notification handler 'handleDownloadListUpdate'
        updateTitle()
        // No need to manually remove from 'downloads' array or delete rows here if relying on notification
    }

    // **FIXED:** Add showAlert helper
    private func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alertController, animated: true, completion: nil)
    }
}

extension DownloadListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return downloads.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "DownloadCell", for: indexPath) as? DownloadCell else {
            return UITableViewCell()
        }
        
        let downloadItem = downloads[indexPath.row]
        cell.titleLabel.text = downloadItem.title
        
         if downloadItem.format == .mp4, let fileURL = downloadItem.completedFileURL {
             do {
                 let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                 let fileSize = attributes[.size] as? Int64 ?? 0
                 cell.fileSizeLabel.text = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
             } catch {
                 print("Error getting file size: \(error.localizedDescription)")
                 cell.fileSizeLabel.text = "Unknown size"
             }
         } else if downloadItem.format == .hls {
             if let expectedSize = downloadItem.totalBytesExpected, expectedSize > 0 {
                 cell.fileSizeLabel.text = ByteCountFormatter.string(fromByteCount: expectedSize, countStyle: .file) + " (Est.)"
             } else {
                  cell.fileSizeLabel.text = "HLS Stream"
             }
         } else {
             cell.fileSizeLabel.text = "Unknown size"
         }
        
        let interaction = UIContextMenuInteraction(delegate: self)
        cell.addInteraction(interaction)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let downloadItem = downloads[indexPath.row]
        playDownload(item: downloadItem)
    }
}

extension DownloadListViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let locationInTableView = interaction.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: locationInTableView) else {
            return nil
        }
        
        let downloadItem = downloads[indexPath.row]
        
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in
            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self.deleteDownload(at: indexPath)
            }
            
            var children: [UIMenuElement] = [deleteAction]
            
            // Allow rename only for MP4
            if downloadItem.format == .mp4 {
                let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                    self.renameDownload(at: indexPath)
                }
                children.insert(renameAction, at: 0) // Add Rename before Delete
            }
            
             // Add share action only for MP4
             if downloadItem.format == .mp4, let fileURL = downloadItem.completedFileURL {
                 let shareAction = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                     self.shareDownload(url: fileURL)
                 }
                 // Insert share after rename (if present) or at the beginning
                 let shareIndex = children.contains(where: { $0.title == "Rename" }) ? 1 : 0
                 children.insert(shareAction, at: shareIndex)
             }
            
            return UIMenu(title: "", children: children)
        }
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath,
              let cell = tableView.cellForRow(at: indexPath) else {
                  return nil
              }
        return UITargetedPreview(view: cell)
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath,
              let cell = tableView.cellForRow(at: indexPath) else {
                  return nil
              }
        return UITargetedPreview(view: cell)
    }
    
    private func renameDownload(at indexPath: IndexPath) {
        let downloadItem = downloads[indexPath.row]
        
         guard downloadItem.format == .mp4, let oldURL = downloadItem.completedFileURL else {
             showAlert(title: "Rename Not Supported", message: "Renaming is currently only supported for MP4 downloads.")
             return
         }
        
        let alertController = UIAlertController(title: "Rename File", message: nil, preferredStyle: .alert)
        
        alertController.addTextField { textField in
            textField.text = (oldURL.lastPathComponent as NSString).deletingPathExtension
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        let renameAction = UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            guard let newName = alertController.textFields?.first?.text,
                  !newName.isEmpty,
                  let self = self else { return }
            
            let fileExtension = oldURL.pathExtension
            let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName).appendingPathExtension(fileExtension)
            
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                
                 // Update the item in the manager's list
                 var updatedItem = downloadItem
                 updatedItem.completedFileURL = newURL
                 // Optionally update title if needed
                 // updatedItem.title = newName

                 self.downloadManager.updateCompletedDownload(item: updatedItem) // Use manager method
                
                // Reload local data and UI
                self.loadDownloads()
                // self.tableView.reloadRows(at: [indexPath], with: .automatic) // Reloading all data is simpler now
                self.updateTitle()
            } catch {
                print("Error renaming file: \(error.localizedDescription)")
                 self.showAlert(title: "Rename Failed", message: "Could not rename the file: \(error.localizedDescription)")
            }
        }
        
        alertController.addAction(cancelAction)
        alertController.addAction(renameAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
     private func shareDownload(url: URL) {
         let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
         if let popoverController = activityViewController.popoverPresentationController {
             popoverController.sourceView = self.view
             popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
             popoverController.permittedArrowDirections = []
         }
         present(activityViewController, animated: true, completion: nil)
     }
}
