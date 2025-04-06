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
    
    private var downloads: [DownloadItem] = [] // Use DownloadItem now
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
        
        // Observe changes from DownloadManager
         NotificationCenter.default.addObserver(self, selector: #selector(handleDownloadListUpdate), name: .downloadCompleted, object: nil)
         NotificationCenter.default.addObserver(self, selector: #selector(handleDownloadListUpdate), name: .downloadListUpdated, object: nil) // Also observe generic updates if needed

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
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: -150)
        ])
    }
    
    @objc private func openInFilesApp() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Unable to access Documents directory")
            return
        }
        
        // For iOS 14+, using the 'shareddocuments://' scheme might be unreliable or disallowed.
        // A more standard way is to just open the URL itself.
        if UIApplication.shared.canOpenURL(documentsURL) {
             // This usually opens the app's container in Files if the app supports it via Info.plist keys
             UIApplication.shared.open(documentsURL, options: [:]) { success in
                 if !success {
                     print("Failed to open Files app directory")
                     // Show an alert to the user maybe?
                 }
             }
        } else {
            print("Cannot open Files app directory")
        }
    }
    
    private func loadDownloads() {
        // Get completed downloads from the manager
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
             // For MP4, we can get size from the file URL
             if downloadItem.format == .mp4, let fileURL = downloadItem.completedFileURL {
                 do {
                     let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                     totalSize += attributes[.size] as? Int64 ?? 0
                 } catch {
                     print("Error getting file size for \(downloadItem.title): \(error.localizedDescription)")
                 }
             } else if downloadItem.format == .hls {
                 // Getting exact HLS size is complex as it's stored internally by AVFoundation.
                 // We could approximate or store the expected size if available during download.
                 // For now, let's use the last known expected size or show N/A.
                 totalSize += downloadItem.totalBytesExpected ?? 0 // Use expected size as approximation
             }
        }
        return totalSize
    }
    
    private func playDownload(item: DownloadItem) {
         guard let contentURL = item.completedFileURL else {
             showAlert(title: "Error", message: "Download location not found.")
             return
         }

         let player: AVPlayer
         if item.format == .hls {
             // For HLS, create AVURLAsset directly from the bookmark location URL
             let asset = AVURLAsset(url: contentURL)
             let playerItem = AVPlayerItem(asset: asset)
             player = AVPlayer(playerItem: playerItem)
             print("Playing HLS from asset location: \(contentURL)")
         } else {
             // For MP4, create player from the file URL
             player = AVPlayer(url: contentURL)
             print("Playing MP4 from file: \(contentURL.path)")
         }

         let playerViewController = NormalPlayer() // Use NormalPlayer if it has custom logic
         playerViewController.player = player

         present(playerViewController, animated: true) {
             player.play()
         }
     }

    private func deleteDownload(at indexPath: IndexPath) {
        let itemToDelete = downloads[indexPath.row]
        // Call the manager to delete the item and its file
        downloadManager.deleteCompletedDownload(item: itemToDelete)
        // The loadDownloads method will be called via notification observer,
        // or you can call it directly if preferred after deletion.
        // loadDownloads() // Call loadDownloads directly or rely on notification
        updateTitle()
        NotificationCenter.default.post(name: .downloadListUpdated, object: nil) // Ensure UI elsewhere updates
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
        
        // Display file size
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
             // Show estimated size for HLS if available
             if let expectedSize = downloadItem.totalBytesExpected, expectedSize > 0 {
                 cell.fileSizeLabel.text = ByteCountFormatter.string(fromByteCount: expectedSize, countStyle: .file) + " (Estimated)"
             } else {
                  cell.fileSizeLabel.text = "HLS Stream" // Or "Unknown size"
             }
         } else {
             cell.fileSizeLabel.text = "Unknown size"
         }
        
        // Add context menu interaction
        let interaction = UIContextMenuInteraction(delegate: self)
        cell.addInteraction(interaction) // Add interaction to the cell itself
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80 // Maintain previous height or adjust as needed
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let downloadItem = downloads[indexPath.row]
        playDownload(item: downloadItem)
    }
}

// Add UIContextMenuInteractionDelegate extension
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
            
            let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                self.renameDownload(at: indexPath)
            }
            
            // Add share action only if it's a file we can directly share (MP4)
             var children = [renameAction, deleteAction]
             if downloadItem.format == .mp4, let fileURL = downloadItem.completedFileURL {
                 let shareAction = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                     self.shareDownload(url: fileURL)
                 }
                 children.insert(shareAction, at: 0) // Add Share at the beginning
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
        
        // Cannot easily rename HLS downloads managed by AVFoundation
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
                // Update the DownloadItem's URL and potentially title if needed
                 var updatedItem = downloadItem
                 updatedItem.completedFileURL = newURL
                 // Maybe update title too?
                 // updatedItem.title = newName // Or keep original title? Decide based on UX preference.

                // Update the data source array
                 self.downloads[indexPath.row] = updatedItem
                 self.downloadManager.completedDownloads[indexPath.row] = updatedItem // Update manager's array
                 self.downloadManager.saveCompletedDownloads() // Persist the change
                
                // Reload the specific row
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
                self.updateTitle() // Update total size display
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
         // Prevent anchoring issues on iPad
         if let popoverController = activityViewController.popoverPresentationController {
             popoverController.sourceView = self.view
             popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
             popoverController.permittedArrowDirections = []
         }
         present(activityViewController, animated: true, completion: nil)
     }
}
