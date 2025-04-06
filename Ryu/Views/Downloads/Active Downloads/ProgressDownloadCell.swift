import UIKit

protocol ProgressDownloadCellDelegate: AnyObject {
    // Pass the unique ID back to the delegate
    func cancelDownload(for cell: ProgressDownloadCell, downloadId: String)
}

class ProgressDownloadCell: UIView {
    weak var delegate: ProgressDownloadCellDelegate?
    private var downloadId: String? // Store the ID

    private let backgroundContentView: UIView = {
        let view = UIView()
        view.backgroundColor = .quaternarySystemFill
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 2 // Allow multi-line titles
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.tintColor = .systemTeal // Use accent color
        progress.trackTintColor = .systemGray4
        return progress
    }()
    
    private let percentageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupContextMenuInteraction()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        // No need for explicit background color on self if backgroundContentView covers it
        layer.cornerRadius = 12
        layer.masksToBounds = true // Apply corner radius to the cell itself
        
        addSubview(backgroundContentView)
        backgroundContentView.addSubview(titleLabel)
        backgroundContentView.addSubview(progressView)
        backgroundContentView.addSubview(percentageLabel)
        
        NSLayoutConstraint.activate([
            // backgroundContentView constraints (same as before)
            backgroundContentView.topAnchor.constraint(equalTo: topAnchor),
            backgroundContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundContentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: backgroundContentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: backgroundContentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: backgroundContentView.trailingAnchor, constant: -12),
            
            progressView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: backgroundContentView.leadingAnchor, constant: 12),
            // Give space for the percentage label
            progressView.trailingAnchor.constraint(equalTo: percentageLabel.leadingAnchor, constant: -8),
            progressView.heightAnchor.constraint(equalToConstant: 8), // Slightly thicker progress bar
            
            percentageLabel.centerYAnchor.constraint(equalTo: progressView.centerYAnchor),
            percentageLabel.trailingAnchor.constraint(equalTo: backgroundContentView.trailingAnchor, constant: -12),
            // Set minimum width for percentage label
            percentageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            
            // Ensure backgroundContentView bottom is tied to the lowest element
            backgroundContentView.bottomAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12)
        ])
    }
    
    private func setupContextMenuInteraction() {
        let interaction = UIContextMenuInteraction(delegate: self)
        addInteraction(interaction) // Add interaction to the cell view itself
    }
    
    // Updated configure method
    func configure(with title: String, progress: Float, downloadId: String) {
        self.titleLabel.text = title
        self.downloadId = downloadId // Store the ID
        updateProgress(progress)
    }
    
    func updateProgress(_ progress: Float) {
        progressView.setProgress(progress, animated: true) // Animate progress changes
        percentageLabel.text = String(format: "%.0f%%", progress * 100)
    }
}

extension ProgressDownloadCell: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ -> UIMenu? in
            guard let self = self else { return nil }

            let copyTitleAction = UIAction(title: "Copy Title", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = self.titleLabel.text
            }
            
            // Pass the stored downloadId to the delegate
            let cancelDownloadAction = UIAction(title: "Cancel Download", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { _ in
                 if let id = self.downloadId {
                     self.delegate?.cancelDownload(for: self, downloadId: id)
                 }
            }
            
            return UIMenu(title: "", children: [copyTitleAction, cancelDownloadAction])
        }
    }
}
