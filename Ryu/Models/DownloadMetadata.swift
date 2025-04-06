struct DownloadMetadata: Codable {
    let id: String
    let url: URL
    let title: String
    var state: DownloadState
    var progress: Float
    let createdAt: Date
    var fileSize: Int64?
    
    enum CodingKeys: String, CodingKey {
        case id
        case url
        case title
        case state
        case progress
        case createdAt
        case fileSize
    }
}

enum DownloadState: Codable {
    case queued
    case downloading(progress: Float, speed: Int64)
    case paused
    case completed
    case failed(String)
    case cancelled
    
    var progress: Float {
        switch self {
        case .queued:
            return 0
        case .downloading(let progress, _):
            return progress
        case .paused:
            return 0
        case .completed:
            return 1
        case .failed, .cancelled:
            return 0
        }
    }
    
    var speed: Int64 {
        switch self {
        case .downloading(_, let speed):
            return speed
        default:
            return 0
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "queued":
            self = .queued
        case "downloading":
            let progress = try container.decode(Float.self, forKey: .progress)
            let speed = try container.decode(Int64.self, forKey: .speed)
            self = .downloading(progress: progress, speed: speed)
        case "paused":
            self = .paused
        case "completed":
            self = .completed
        case "failed":
            let error = try container.decode(String.self, forKey: .error)
            self = .failed(error)
        case "cancelled":
            self = .cancelled
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown state type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .queued:
            try container.encode("queued", forKey: .type)
        case .downloading(let progress, let speed):
            try container.encode("downloading", forKey: .type)
            try container.encode(progress, forKey: .progress)
            try container.encode(speed, forKey: .speed)
        case .paused:
            try container.encode("paused", forKey: .type)
        case .completed:
            try container.encode("completed", forKey: .type)
        case .failed(let error):
            try container.encode("failed", forKey: .type)
            try container.encode(error, forKey: .error)
        case .cancelled:
            try container.encode("cancelled", forKey: .type)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case progress
        case speed
        case error
    }
} 