//
//  DownloadsViewController.swift
//  Ryu
//
//  Created by Francesco on 16/07/24.
//

import UIKit
import AVKit
import AVFoundation
import Combine

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
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var downloads: [URL] = []
    private let downloadManager = DownloadManager.shared
    private let refreshControl = UIRefreshControl()
    private var cancellables = Set<AnyCancellable>()
    
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
        "No downloads available. It's like they've gone off to a secret party.",
        "Nothing here. Maybe the downloads are waiting for a dramatic entrance."
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupTableView()
        setupNotifications()
        loadDownloads()
    }
    
    private func setupViews() {
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }
    
    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DownloadCell.self, forCellReuseIdentifier: "DownloadCell")
        
        refreshControl.addTarget(self, action: #selector(refreshDownloads), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .downloadListUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadDownloads()
            }
            .store(in: &cancellables)
    }
    
    @objc private func refreshDownloads() {
        loadDownloads()
        refreshControl.endRefreshing()
    }
    
    @objc private func openInFilesApp() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Unable to access Documents directory")
            return
        }
        
        let urlString = documentsURL.absoluteString.replacingOccurrences(of: "file://", with: "shareddocuments://")
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    print("Failed to open Files app")
                }
            }
        } else {
            print("Cannot open Files app")
        }
    }
    
    private func loadDownloads() {
        let fileManager = FileManager.default
        let downloadsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads")
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil)
            downloads = fileURLs.filter { $0.pathExtension.lowercased() == "mp4" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            
            tableView.reloadData()
            emptyStateLabel.isHidden = !downloads.isEmpty
            updateTitle()
            
            if downloads.isEmpty {
                emptyStateLabel.text = emptyMessages.randomElement()
            }
        } catch {
            print("Error loading downloads: \(error.localizedDescription)")
            showAlert(title: "Error", message: "Failed to load downloads: \(error.localizedDescription)")
        }
    }
    
    private func updateTitle() {
        let totalSize = calculateTotalDownloadSize()
        let formattedSize = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        title = "Downloads (\(formattedSize))"
    }
    
    private func calculateTotalDownloadSize() -> Int64 {
        var totalSize: Int64 = 0
        for download in downloads {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: download.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                totalSize += fileSize
            } catch {
                print("Error getting file size: \(error.localizedDescription)")
            }
        }
        return totalSize
    }
    
    private func playDownload(url: URL) {
        guard url.pathExtension.lowercased() == "mp4" else {
            showAlert(title: "Error", message: "This file type is not supported yet.")
            return
        }
        
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        
        let player = AVPlayer(playerItem: playerItem)
        
        let playerViewController = NormalPlayer()
        playerViewController.player = player
        
        present(playerViewController, animated: true) {
            player.play()
        }
    }
    
    private func deleteDownload(at indexPath: IndexPath) {
        let download = downloads[indexPath.row]
        do {
            try FileManager.default.removeItem(at: download)
            downloads.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            loadDownloads()
            updateTitle()
            
            NotificationCenter.default.post(name: .downloadListUpdated, object: nil)
        } catch {
            print("Error deleting file: \(error.localizedDescription)")
            showAlert(title: "Error", message: "Failed to delete file: \(error.localizedDescription)")
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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
        
        let download = downloads[indexPath.row]
        cell.titleLabel.text = (download.lastPathComponent as NSString).deletingPathExtension
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: download.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            cell.fileSizeLabel.text = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        } catch {
            print("Error getting file size: \(error.localizedDescription)")
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
        tableView.deselectRow(at: indexPath, animated: true)
        let download = downloads[indexPath.row]
        playDownload(url: download)
    }
}

extension DownloadListViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let cell = interaction.view as? DownloadCell,
              let indexPath = tableView.indexPath(for: cell) else { return nil }
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.deleteDownload(at: indexPath)
            }
            
            let openInFilesAction = UIAction(title: "Open in Files", image: UIImage(systemName: "folder")) { [weak self] _ in
                self?.openInFilesApp()
            }
            
            return UIMenu(children: [deleteAction, openInFilesAction])
        }
    }
}

class DownloadCell: UITableViewCell {
    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let fileSizeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        contentView.addSubview(fileSizeLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            fileSizeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            fileSizeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            fileSizeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            fileSizeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
}
