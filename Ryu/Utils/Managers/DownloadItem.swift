import Foundation

struct DownloadItem: Identifiable, Codable {
    let id: String // Unique identifier (e.g., source URL string or UUID)
    let title: String // User-friendly title (e.g., "Anime Title - Ep 1")
    let sourceURL: URL // Original URL to download from
    var downloadTaskIdentifier: Int? // To map URLSession delegate calls back to the item
    var progress: Float = 0.0
    var status: DownloadStatus = .pending
    var format: DownloadFormat
    var completedFileURL: URL? // Local URL (file path for MP4, asset location for HLS)
    var totalBytesExpected: Int64? // For progress calculation if available
    var totalBytesWritten: Int64?  // For progress calculation if available
    var errorDescription: String? // Store error message on failure

    enum DownloadStatus: String, Codable {
        case pending      // Waiting to start
        case downloading  // Actively downloading
        case paused       // Download paused (Optional TODO)
        case completed    // Download finished successfully
        case failed       // Download failed
        case cancelled    // Download cancelled by user
    }

    enum DownloadFormat: String, Codable {
        case mp4
        case hls
        case unknown
    }

    // CodingKeys needed because downloadTaskIdentifier is optional and potentially transient if not persisted
    enum CodingKeys: String, CodingKey {
        case id, title, sourceURL, progress, status, format, completedFileURL, totalBytesExpected, totalBytesWritten, errorDescription
        // Exclude downloadTaskIdentifier from Codable persistence if desired
    }

    // Helper to get a displayable progress string
    var progressString: String {
        String(format: "%.0f%%", progress * 100)
    }

    // Helper to get file size string if available
    var fileSizeString: String {
        guard let totalBytes = totalBytesExpected, totalBytes > 0 else { return "N/A" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}
