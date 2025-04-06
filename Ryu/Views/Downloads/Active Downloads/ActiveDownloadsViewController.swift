//
//  ActiveDownloadsViewController.swift
//  Ryu
//
//  Created by Francesco on 01/08/24.
//

import UIKit
import Combine

class ActiveDownloadsViewController: UIViewController {
    private let tableView: UITableView = {
        let table = UITableView()
        table.register(ProgressDownloadCell.self, forCellReuseIdentifier: ProgressDownloadCell.identifier)
        table.separatorStyle = .none
        return table
    }()
    
    private var activeDownloads: [DownloadMetadata] = []
    private let downloadManager = DownloadManager.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupTableView()
        setupNotifications()
        loadActiveDownloads()
    }
    
    private func setupViews() {
        view.backgroundColor = .systemBackground
        view.addSubview(tableView)
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadUpdate),
            name: .downloadDidUpdate,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadComplete),
            name: .downloadDidComplete,
            object: nil
        )
    }
    
    private func loadActiveDownloads() {
        activeDownloads = downloadManager.getActiveDownloads()
        tableView.reloadData()
    }
    
    @objc private func handleDownloadUpdate(_ notification: Notification) {
        guard let metadata = notification.userInfo?["metadata"] as? DownloadMetadata else { return }
        
        if let index = activeDownloads.firstIndex(where: { $0.id == metadata.id }) {
            activeDownloads[index] = metadata
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        }
    }
    
    @objc private func handleDownloadComplete(_ notification: Notification) {
        guard let metadata = notification.userInfo?["metadata"] as? DownloadMetadata else { return }
        
        if let index = activeDownloads.firstIndex(where: { $0.id == metadata.id }) {
            activeDownloads.remove(at: index)
            tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
        }
    }
}

extension ActiveDownloadsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return activeDownloads.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ProgressDownloadCell.identifier, for: indexPath) as? ProgressDownloadCell else {
            return UITableViewCell()
        }
        
        let metadata = activeDownloads[indexPath.row]
        cell.delegate = self
        cell.configure(with: metadata)
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100
    }
}

extension ActiveDownloadsViewController: ProgressDownloadCellDelegate {
    func progressDownloadCell(_ cell: ProgressDownloadCell, didTapPauseResume id: String) {
        if let metadata = activeDownloads.first(where: { $0.id == id }) {
            switch metadata.state {
            case .downloading, .queued:
                downloadManager.pauseDownload(id: id)
            case .paused:
                downloadManager.resumeDownload(id: id)
            default:
                break
            }
        }
    }
    
    func progressDownloadCell(_ cell: ProgressDownloadCell, didTapCancel id: String) {
        downloadManager.cancelDownload(id: id)
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
