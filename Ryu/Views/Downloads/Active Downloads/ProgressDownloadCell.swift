//
//  ProgressDownloadCell.swift
//  Ryu
//
//  Created by Francesco on 01/08/24.
//

import UIKit

protocol ProgressDownloadCellDelegate: AnyObject {
    func progressDownloadCell(_ cell: ProgressDownloadCell, didTapPauseResume id: String)
    func progressDownloadCell(_ cell: ProgressDownloadCell, didTapCancel id: String)
}

class ProgressDownloadCell: UITableViewCell {
    static let identifier = "ProgressDownloadCell"
    
    weak var delegate: ProgressDownloadCellDelegate?
    private var downloadId: String?
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 2
        return label
    }()
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.tintColor = .systemTeal
        return progress
    }()
    
    private let progressLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private let speedLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private lazy var pauseResumeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        button.tintColor = .systemTeal
        button.addTarget(self, action: #selector(pauseResumeTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .systemRed
        button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return button
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.addSubview(titleLabel)
        contentView.addSubview(progressView)
        contentView.addSubview(progressLabel)
        contentView.addSubview(speedLabel)
        contentView.addSubview(pauseResumeButton)
        contentView.addSubview(cancelButton)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        pauseResumeButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: pauseResumeButton.leadingAnchor, constant: -8),
            
            progressView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
            
            progressLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 4),
            progressLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            
            speedLabel.centerYAnchor.constraint(equalTo: progressLabel.centerYAnchor),
            speedLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            speedLabel.leadingAnchor.constraint(greaterThanOrEqualTo: progressLabel.trailingAnchor, constant: 16),
            
            pauseResumeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            pauseResumeButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -16),
            pauseResumeButton.widthAnchor.constraint(equalToConstant: 44),
            pauseResumeButton.heightAnchor.constraint(equalToConstant: 44),
            
            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    func configure(with metadata: DownloadMetadata) {
        downloadId = metadata.id
        titleLabel.text = metadata.title
        
        switch metadata.state {
        case .queued:
            progressView.progress = 0
            progressLabel.text = "Queued"
            speedLabel.text = ""
            pauseResumeButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
            pauseResumeButton.tintColor = .systemRed
        case .downloading(let progress, let speed):
            progressView.progress = progress
            progressLabel.text = "\(Int(progress * 100))%"
            speedLabel.text = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .binary) + "/s"
            pauseResumeButton.setImage(UIImage(systemName: "pause.circle"), for: .normal)
            pauseResumeButton.tintColor = .systemBlue
        case .paused:
            progressView.progress = metadata.progress
            progressLabel.text = "\(Int(metadata.progress * 100))%"
            speedLabel.text = "Paused"
            pauseResumeButton.setImage(UIImage(systemName: "play.circle"), for: .normal)
            pauseResumeButton.tintColor = .systemGreen
        case .completed:
            progressView.progress = 1
            progressLabel.text = "Completed"
            speedLabel.text = ""
            pauseResumeButton.setImage(UIImage(systemName: "checkmark.circle"), for: .normal)
            pauseResumeButton.tintColor = .systemGreen
        case .failed(let error):
            progressView.progress = 0
            progressLabel.text = "Failed: \(error)"
            speedLabel.text = ""
            pauseResumeButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
            pauseResumeButton.tintColor = .systemRed
        case .cancelled:
            progressView.progress = 0
            progressLabel.text = "Cancelled"
            speedLabel.text = ""
            pauseResumeButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
            pauseResumeButton.tintColor = .systemRed
        }
    }
    
    @objc private func pauseResumeTapped() {
        guard let id = downloadId else { return }
        delegate?.progressDownloadCell(self, didTapPauseResume: id)
    }
    
    @objc private func cancelTapped() {
        guard let id = downloadId else { return }
        delegate?.progressDownloadCell(self, didTapCancel: id)
    }
}
