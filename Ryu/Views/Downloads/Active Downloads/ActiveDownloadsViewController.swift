//
//  ActiveDownloadsViewController.swift
//  Ryu
//
//  Created by Francesco on 01/08/24.
//

import UIKit
import Combine

class ActiveDownloadsViewController: UIViewController {
    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()
    
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "No active downloads"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var downloads: [String: DownloadMetadata] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupNotifications()
        loadDownloads()
        startProgressUpdateTimer()
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
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .downloadCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let id = notification.userInfo?["id"] as? String {
                    self?.downloads.removeValue(forKey: id)
                    self?.updateDownloadViews()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .downloadListUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadDownloads()
            }
            .store(in: &cancellables)
    }
    
    private func loadDownloads() {
        downloads = DownloadManager.shared.getActiveDownloads()
        updateDownloadViews()
    }
    
    private func updateDownloadViews() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            for (id, metadata) in self.downloads {
                let downloadView = ProgressDownloadCell()
                downloadView.configure(with: metadata)
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
    
    private func updateProgress() {
        let activeDownloads = DownloadManager.shared.getActiveDownloads()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            for (id, metadata) in activeDownloads {
                if let downloadView = self.stackView.arrangedSubviews.first(where: { ($0 as? ProgressDownloadCell)?.downloadId == id }) as? ProgressDownloadCell {
                    downloadView.updateProgress(with: metadata)
                }
            }
            
            if activeDownloads != self.downloads {
                self.downloads = activeDownloads
                self.updateDownloadViews()
            }
        }
    }
    
    private func startProgressUpdateTimer() {
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateProgress()
            }
            .store(in: &cancellables)
    }
}

extension ActiveDownloadsViewController: ProgressDownloadCellDelegate {
    func progressDownloadCell(_ cell: ProgressDownloadCell, didRequestPause id: String) {
        DownloadManager.shared.pauseDownload(id: id)
    }
    
    func progressDownloadCell(_ cell: ProgressDownloadCell, didRequestResume id: String) {
        DownloadManager.shared.resumeDownload(id: id)
    }
    
    func progressDownloadCell(_ cell: ProgressDownloadCell, didRequestCancel id: String) {
        DownloadManager.shared.cancelDownload(id: id)
    }
}

class ProgressDownloadCell: UIView {
    weak var delegate: ProgressDownloadCellDelegate?
    var downloadId: String?
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        return progress
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        
        addSubview(titleLabel)
        addSubview(progressView)
        addSubview(statusLabel)
        addSubview(actionButton)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 100),
            
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            progressView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            statusLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            
            actionButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actionButton.widthAnchor.constraint(equalToConstant: 44)
        ])
        
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
    }
    
    func configure(with metadata: DownloadMetadata) {
        downloadId = metadata.id
        titleLabel.text = metadata.title
        
        switch metadata.state {
        case .queued:
            progressView.progress = 0
            statusLabel.text = "Queued"
            actionButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
            actionButton.tintColor = .systemRed
        case .downloading(let progress, let speed):
            progressView.progress = progress
            let speedText = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .binary)
            statusLabel.text = "\(Int(progress * 100))% • \(speedText)/s"
            actionButton.setImage(UIImage(systemName: "pause.circle"), for: .normal)
            actionButton.tintColor = .systemBlue
        case .paused:
            progressView.progress = 0
            statusLabel.text = "Paused"
            actionButton.setImage(UIImage(systemName: "play.circle"), for: .normal)
            actionButton.tintColor = .systemGreen
        case .completed:
            progressView.progress = 1
            statusLabel.text = "Completed"
            actionButton.setImage(UIImage(systemName: "checkmark.circle"), for: .normal)
            actionButton.tintColor = .systemGreen
        case .failed(let error):
            progressView.progress = 0
            statusLabel.text = "Failed: \(error.localizedDescription)"
            actionButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
            actionButton.tintColor = .systemRed
        case .cancelled:
            progressView.progress = 0
            statusLabel.text = "Cancelled"
            actionButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
            actionButton.tintColor = .systemRed
        }
    }
    
    func updateProgress(with metadata: DownloadMetadata) {
        configure(with: metadata)
    }
    
    @objc private func actionButtonTapped() {
        guard let id = downloadId else { return }
        
        switch metadata.state {
        case .queued, .downloading:
            delegate?.progressDownloadCell(self, didRequestPause: id)
        case .paused:
            delegate?.progressDownloadCell(self, didRequestResume: id)
        case .failed, .cancelled:
            delegate?.progressDownloadCell(self, didRequestCancel: id)
        case .completed:
            break
        }
    }
}

protocol ProgressDownloadCellDelegate: AnyObject {
    func progressDownloadCell(_ cell: ProgressDownloadCell, didRequestPause id: String)
    func progressDownloadCell(_ cell: ProgressDownloadCell, didRequestResume id: String)
    func progressDownloadCell(_ cell: ProgressDownloadCell, didRequestCancel id: String)
}
