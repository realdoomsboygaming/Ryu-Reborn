import UIKit

class ActiveDownloadsViewController: UIViewController, ProgressDownloadCellDelegate {
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No active downloads. You can start one by clicking the download button next to each episode."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var downloads: [DownloadItem] = [] // Use DownloadItem
    private var progressUpdateTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupViews()
        loadDownloads()
        startProgressUpdateTimer()
        
        // Observe download completion
        NotificationCenter.default.addObserver(self, selector: #selector(downloadCompletedOrFailed(_:)), name: .downloadCompleted, object: nil)
         // Observe potential failures that might remove items from active list
         NotificationCenter.default.addObserver(self, selector: #selector(downloadCompletedOrFailed(_:)), name: Notification.Name("DownloadFailedNotification"), object: DownloadManager.shared) // Assuming DownloadManager posts this on failure

    }
    
     deinit {
         progressUpdateTimer?.invalidate()
         NotificationCenter.default.removeObserver(self)
     }

    private func setupViews() {
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        view.addSubview(emptyStateLabel)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }
    
    private func loadDownloads() {
        // Get active downloads from the manager
        downloads = DownloadManager.shared.getActiveDownloadItems()
        updateDownloadViews()
    }
    
    private func updateDownloadViews() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Simple reload for now, could optimize later
            self.stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            for downloadItem in self.downloads {
                let downloadView = ProgressDownloadCell()
                // Pass the item ID for cancellation context
                downloadView.configure(with: downloadItem.title, progress: downloadItem.progress, downloadId: downloadItem.id)
                downloadView.delegate = self
                self.stackView.addArrangedSubview(downloadView)
            }
            
            self.updateEmptyState()
        }
    }
    
    private func updateEmptyState() {
        emptyStateLabel.isHidden = !downloads.isEmpty
        scrollView.isHidden = downloads.isEmpty
    }
    
    // This timer updates progress frequently
    private func updateProgress() {
        let activeDownloadItems = DownloadManager.shared.getActiveDownloadItems()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update existing cells or reload if counts differ significantly
            if activeDownloadItems.count == self.stackView.arrangedSubviews.count {
                for (index, item) in activeDownloadItems.enumerated() {
                     if let cell = self.stackView.arrangedSubviews[index] as? ProgressDownloadCell {
                        cell.updateProgress(item.progress)
                     }
                }
                // Update local data source if needed (e.g., if status changed)
                 self.downloads = activeDownloadItems
            } else {
                 // If count differs, reload everything for simplicity
                 self.downloads = activeDownloadItems
                 self.updateDownloadViews()
            }
        }
    }
    
    private func startProgressUpdateTimer() {
        progressUpdateTimer?.invalidate() // Invalidate existing timer first
        progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    // Delegate method from ProgressDownloadCell
    func cancelDownload(for cell: ProgressDownloadCell, downloadId: String) {
        // Use the downloadId passed from the cell
        DownloadManager.shared.cancelDownload(for: downloadId)
        
        // Remove from local array and update UI immediately
        if let index = downloads.firstIndex(where: { $0.id == downloadId }) {
            downloads.remove(at: index)
            // Animate removal from stack view
            UIView.animate(withDuration: 0.3, animations: {
                 cell.isHidden = true // Hide immediately
                 cell.alpha = 0
             }) { _ in
                 cell.removeFromSuperview()
                 self.updateEmptyState()
             }
        }
    }
    
    // Called when a download finishes (successfully or failed)
    @objc private func downloadCompletedOrFailed(_ notification: Notification) {
        // Reload the list from the DownloadManager to reflect the change
        loadDownloads()
    }
}
