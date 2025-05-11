import CoreLocation

struct EmojiPin: Identifiable, Codable {
    var id: Int
    var latitude: Double
    var longitude: Double
    var emoji: String
    var comment: String
    var zoomLevel: Double
    var createdAt: Date
    var updatedAt: Date
    var isCurrentUserPin: Bool = false  // New property with default value
    var upvotes: Int
    var isLiked: Bool
    var isNew: Bool
    var isTrending: Bool
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // If you have an initializer, update it to include the new property
    init(id: Int, latitude: Double, longitude: Double, emoji: String, comment: String,
             zoomLevel: Double, createdAt: Date = Date(), updatedAt: Date, upvotes: Int, isLiked: Bool,
             isNew: Bool, isTrending: Bool = false, isCurrentUserPin: Bool = false) {
            self.id = id
            self.latitude = latitude
            self.longitude = longitude
            self.emoji = emoji
            self.comment = comment
            self.zoomLevel = zoomLevel
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isCurrentUserPin = isCurrentUserPin
            self.upvotes = upvotes
            self.isLiked = isLiked
            self.isNew = isNew
            self.isTrending = isTrending
        }
    }
