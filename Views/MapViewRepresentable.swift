import SwiftUI
import MapboxMaps
import CoreLocation
import UIKit

class MapCameraState: ObservableObject {
    @Published var zoomLevel: Double = 0.0
    @Published var camera: CameraOptions? = nil
    @Published var isUserLocationVisible: Bool = true
    
    func centerToUserLocation(_ location: CLLocation?) {
        guard let location = location else { return }
        
        // Create camera options for MapboxMaps
        self.camera = CameraOptions(
            center: location.coordinate,
            zoom: 16.0,
            bearing: 0,
            pitch: 0
        )
        
        // Notify observers
        objectWillChange.send()
    }
    
    // Add this new method for navigating to a pin location
    func centerToLocation(_ coordinate: CLLocationCoordinate2D, zoomLevel: Double) {
        // Create camera options for MapboxMaps
        self.camera = CameraOptions(
            center: coordinate,
            zoom: zoomLevel,
            bearing: 0,
            pitch: 0
        )
        
        // Notify observers
        objectWillChange.send()
    }
}

struct UserLocationView: View {
    var body: some View {
        ZStack {
            // User location circle pin
            Circle()
                .fill(Color.customPink)
                .frame(width: 16, height: 16)
            
            // White border
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 16, height: 16)
        }
    }
}

// MARK: - Main Map View Representable

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var userLocation: CLLocation?
    /// Array of emoji pins to display on the map.
    var emojiPins: [EmojiPin]
    /// Shared camera state.
    @ObservedObject var cameraState: MapCameraState
    var viewModel: EmojiPinViewModel
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(cameraState: cameraState, viewModel: viewModel)
    }
    
    func makeUIView(context: Context) -> MapView {
        // Set your Mapbox access token
        MapboxOptions.accessToken = AppConfig.mapboxApiKey
        
        let mapInitOptions = MapInitOptions(styleURI: .streets)
        let mapView = MapView(frame: .zero, mapInitOptions: mapInitOptions)
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Lock map to 2D (disable rotation and pitch)
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false
        
        let coordinator = context.coordinator
        coordinator.mapView = mapView
        coordinator.annotationManager = mapView.annotations.makePointAnnotationManager()
        
        // Add tap gesture recognizer to dismiss context menus when tapping on the map
        let tapGesture = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleMapTap))
        tapGesture.delegate = coordinator
        mapView.addGestureRecognizer(tapGesture)
        
        // Listen for camera changes to update pins and user location puck
        mapView.mapboxMap.onEvery(event: .cameraChanged) { _ in
            DispatchQueue.main.async {
                let newZoom = mapView.mapboxMap.cameraState.zoom
                if newZoom != coordinator.cameraState.zoomLevel {
                    coordinator.cameraState.zoomLevel = newZoom
                    coordinator.scheduleEmojiPinUpdate(with: emojiPins)
                }
                
                // Check if user location is visible
                if let userLocation = coordinator.currentUserLocation {
                    let isVisible = coordinator.isUserLocationVisible(in: mapView)
                    self.cameraState.isUserLocationVisible = isVisible
                }
            }
        }
        
        mapView.mapboxMap.onNext(event: .mapIdle) { _ in
            DispatchQueue.main.async {
                let newZoom = mapView.mapboxMap.cameraState.zoom
                if newZoom != coordinator.cameraState.zoomLevel {
                    coordinator.cameraState.zoomLevel = newZoom
                    coordinator.scheduleEmojiPinUpdate(with: emojiPins)
                }
                coordinator.updateUserLocationPuck(in: mapView)
            }
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        // Set the initial camera if not yet set
        if let location = userLocation, !context.coordinator.hasSetInitialCamera {
            let cameraOptions = CameraOptions(center: location.coordinate, zoom: 16)
            mapView.mapboxMap.setCamera(to: cameraOptions)
            context.coordinator.hasSetInitialCamera = true
        }
        if let cameraOptions = cameraState.camera {
            // Cancel any ongoing camera animations (including scroll momentum)
            mapView.camera.cancelAnimations()
            mapView.mapboxMap.setCamera(to: cameraOptions)
            DispatchQueue.main.async {
                 self.cameraState.camera = nil
            }
        }
        
        // Update the current user location and trigger pin/puck updates.
        context.coordinator.currentUserLocation = userLocation
        context.coordinator.scheduleEmojiPinUpdate(with: emojiPins)
        context.coordinator.updateUserLocationPuck(in: mapView)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var mapView: MapView?
        var annotationManager: AnnotationManager?
        
        var cameraState: MapCameraState
        var viewModel: EmojiPinViewModel
        var hasSetInitialCamera = false
        
        // For SwiftUI-based annotation views.
        var annotationViews: [String: UIView] = [:]
        
        // Debounce timer for pin updates.
        var debounceTimer: Timer?
        
        // Store the current user location.
        var currentUserLocation: CLLocation?
        
        // Custom user location puck view.
        var userLocationPuck: UIView?
        
        // Optional debug overlay for bounding boxes.
        private var debugOverlayView: UIView?
        
        init(cameraState: MapCameraState, viewModel: EmojiPinViewModel) {
                self.cameraState = cameraState
                self.viewModel = viewModel
                super.init()
            }
        
        // Handle tap on map to dismiss any active pin context menus
        @objc func handleMapTap() {
            // Deactivate any active pin when the map is tapped
            LongPressManager.shared.deactivateAllPins()
        }
        
        // Allow the tap gesture to work alongside other gestures
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        // Prevent the tap gesture from intercepting touches on pins
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Only handle taps on the map background, not on annotation views
            if touch.view is HostingViewWrapper || touch.view?.superview is HostingViewWrapper {
                return false
            }
            return true
        }
        
        func isUserLocationVisible(in mapView: MapView) -> Bool {
            guard let userLocation = currentUserLocation else { return false }
            
            let viewportWidth = mapView.frame.width
            let viewportHeight = mapView.frame.height
            let userLocationPoint = mapView.mapboxMap.point(for: userLocation.coordinate)
            
            let isOnScreen = userLocationPoint.x >= 0 &&
                             userLocationPoint.x <= viewportWidth &&
                             userLocationPoint.y >= 0 &&
                             userLocationPoint.y <= viewportHeight
            
            return isOnScreen
        }
        
        // MARK: - Custom User Location Puck
        
        func updateUserLocationPuck(in mapView: MapView) {
            guard let userLocation = currentUserLocation else {
                userLocationPuck?.removeFromSuperview()
                userLocationPuck = nil
                return
            }
            
            if !isUserLocationVisible(in: mapView) {
                userLocationPuck?.removeFromSuperview()
                userLocationPuck = nil
                return
            }
            
            // Convert the user's coordinate to a screen point.
            let userScreenPoint = mapView.mapboxMap.point(for: userLocation.coordinate)
            
            // Create the puck if it doesn't exist.
            if userLocationPuck == nil {
                let hostingController = UIHostingController(rootView: UserLocationView())
                hostingController.view.backgroundColor = .clear
                hostingController.view.translatesAutoresizingMaskIntoConstraints = true // We'll manage its frame manually.
                mapView.addSubview(hostingController.view)
                userLocationPuck = hostingController.view
            }
            
            // Update the puck's frame to keep it centered on the user location.
            if let puckView = userLocationPuck {
                let puckSize: CGFloat = 40.0
                puckView.frame = CGRect(
                    x: userScreenPoint.x - puckSize / 2,
                    y: userScreenPoint.y - puckSize / 2,
                    width: puckSize,
                    height: puckSize
                )
            }
        }
        
        // MARK: - Emoji Pin Updates
        
        func scheduleEmojiPinUpdate(with pins: [EmojiPin], delay: TimeInterval = 0.3) {
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.updateEmojiPins(pins: pins)
            }
        }
        
        func updateEmojiPins(pins: [EmojiPin]) {
            guard let mapView = mapView else { return }
            
            // Remove any existing debug overlay.
            debugOverlayView?.removeFromSuperview()
            let debugOverlay = UIView(frame: mapView.bounds)
            debugOverlay.backgroundColor = .clear
            debugOverlay.isUserInteractionEnabled = false
            mapView.addSubview(debugOverlay)
            self.debugOverlayView = debugOverlay
            
            var usedRects: [CGRect] = []
            var newIDs = Set<String>()
            
            // Iterate through all emoji pins.
            for (index, pin) in pins.enumerated() {
                let viewID = "emoji-\(pin.id)"
                newIDs.insert(viewID)
                
                // Decide whether to show the comment based on the current zoom level.
                let showComment = (cameraState.zoomLevel >= pin.zoomLevel)
                
                // Build or reuse the SwiftUI annotation view.
                let annotationView = getOrCreateView(for: pin, id: viewID, showComment: showComment)
                
                // Measure the view's bounding size.
                let (boundingWidth, boundingHeight) = measure(annotationView)
                
                // Generate a stable random vector for this pin (based on its id).
                let randomVec = randomNormalizedVector(seed: pin.id)
                
                // Find a collision-free coordinate for the annotation.
                let finalCoordinate = findCollisionFreeCoordinate(
                    pin: pin,
                    baseCoordinate: pin.coordinate,
                    randomVector: randomVec,
                    boundingWidth: boundingWidth,
                    boundingHeight: boundingHeight,
                    showComment: showComment,
                    usedRects: &usedRects,
                    in: mapView
                )
                
                // Define view annotation options.
                let options = ViewAnnotationOptions(
                    geometry: Point(finalCoordinate),
                    width: boundingWidth,
                    height: boundingHeight,
                    allowOverlap: true,
                    anchor: .center
                )
                do {
                    if mapView.viewAnnotations.options(for: annotationView) != nil {
                        try mapView.viewAnnotations.update(annotationView, options: options)
                    } else {
                        try mapView.viewAnnotations.add(annotationView, id: viewID, options: options)
                    }
                } catch {
                    print("Failed to add/update annotation:", error)
                }
            }
            
            // Remove old annotations that are no longer used.
            for (id, view) in annotationViews {
                if !newIDs.contains(id) {
                    mapView.viewAnnotations.remove(view)
                    annotationViews.removeValue(forKey: id)
                }
            }
        }
        
        // MARK: - Collision Helpers
        
        func randomNormalizedVector(seed: Int) -> CGVector {
            var hash = UInt32(truncatingIfNeeded: seed)
            hash ^= hash >> 16
            hash &*= 0x85ebca6b
            hash ^= hash >> 13
            hash &*= 0xc2b2ae35
            hash ^= hash >> 16
            
            let randomFraction = Double(hash) / Double(UInt32.max)
            let angle = randomFraction * 2.0 * Double.pi
            return CGVector(dx: cos(angle), dy: sin(angle))
        }
        
        func coordinate(
            from coordinate: CLLocationCoordinate2D,
            distanceMeters: Double,
            bearingDegrees: Double
        ) -> CLLocationCoordinate2D {
            let earthRadius = 6378137.0 // in meters
            let bearing = bearingDegrees * .pi / 180
            let lat1 = coordinate.latitude * .pi / 180
            let lon1 = coordinate.longitude * .pi / 180

            let lat2 = asin(sin(lat1) * cos(distanceMeters / earthRadius) +
                            cos(lat1) * sin(distanceMeters / earthRadius) * cos(bearing))
            let lon2 = lon1 + atan2(sin(bearing) * sin(distanceMeters / earthRadius) * cos(lat1),
                                    cos(distanceMeters / earthRadius) - sin(lat1) * sin(lat2))
            
            return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
        }
        
        func findCollisionFreeCoordinate(
            pin: EmojiPin,
            baseCoordinate: CLLocationCoordinate2D,
            randomVector: CGVector,
            boundingWidth: CGFloat,
            boundingHeight: CGFloat,
            showComment: Bool,
            usedRects: inout [CGRect],
            in mapView: MapView,
            stepMeters: Double = 1.0
        ) -> CLLocationCoordinate2D {
            
            // Helper: Calculate the collision rect from a screen point.
                func collisionRect(for screenPoint: CGPoint) -> CGRect {
                    // Make the bounding box larger if the pin has badges
                    let extraHeight: CGFloat = (pin.isNew && pin.isTrending) ? 25 :
                                              (pin.isNew || pin.isTrending) ? 15 : 0
                    
                    if showComment {
                        var modifiedBoundingHeight = boundingHeight + extraHeight
                        var extraMoveDown: CGFloat = 25
                        if pin.comment.count <= 26 {
                            extraMoveDown = 0
                        } else {
                            modifiedBoundingHeight += 10.0
                        }
                        return CGRect(
                            x: screenPoint.x - boundingWidth / 2,
                            y: screenPoint.y - boundingHeight / 2 + extraMoveDown,
                            width: boundingWidth,
                            height: modifiedBoundingHeight
                        )
                    } else {
                        let halfWidth = boundingWidth / 2
                        let halfHeight = (boundingHeight + extraHeight) / 2
                        return CGRect(
                            x: screenPoint.x - halfWidth / 2,
                            y: screenPoint.y - halfHeight / 2,
                            width: halfWidth,
                            height: halfHeight
                        )
                    }
                }
            
            var candidateCoordinate = baseCoordinate
            var candidateScreenPoint = mapView.mapboxMap.point(for: candidateCoordinate)
            var candidateRect = collisionRect(for: candidateScreenPoint)
            
            let baseAngle = atan2(randomVector.dy, randomVector.dx)
            let bearing = (baseAngle * 180 / .pi + 90).truncatingRemainder(dividingBy: 360)
            
            var i = 0
            while usedRects.contains(where: { $0.intersects(candidateRect) }) {
                candidateCoordinate = coordinate(from: candidateCoordinate, distanceMeters: stepMeters, bearingDegrees: bearing)
                candidateScreenPoint = mapView.mapboxMap.point(for: candidateCoordinate)
                candidateRect = collisionRect(for: candidateScreenPoint)
                i += 1
                if i == 10 {
                    break
                }
            }
            
            usedRects.append(candidateRect)
            return candidateCoordinate
        }
        
        // Measure the SwiftUI-based pin view's bounding size.
        private func measure(_ annotationView: UIView) -> (CGFloat, CGFloat) {
            annotationView.setNeedsLayout()
            annotationView.layoutIfNeeded()
            
            let targetSize = CGSize(width: 200, height: UIView.layoutFittingCompressedSize.height)
            let fittedSize = annotationView.systemLayoutSizeFitting(
                targetSize,
                withHorizontalFittingPriority: .fittingSizeLevel,
                verticalFittingPriority: .fittingSizeLevel
            )
            
            let margin: CGFloat = 10
            return (fittedSize.width + margin, fittedSize.height + margin)
        }
        
        // Build or update the SwiftUI-based view for an emoji pin.
        private func getOrCreateView(for pin: EmojiPin, id: String, showComment: Bool) -> UIView {
            if let existingView = annotationViews[id] {
                if let hosting = existingView as? HostingViewWrapper {
                    hosting.hostingController.rootView = EmojiPinView(
                        emoji: pin.emoji,
                        showComment: showComment,
                        emojiFontSize: 30,
                        postID: pin.id,
                        upvotes: pin.upvotes,
                        isLiked: pin.isLiked,
                        isNew: pin.isNew,
                        isTrending: pin.isTrending,
                        comment: pin.comment,
                        commentFontSize: 15,
                        isCurrentUserPin: pin.isCurrentUserPin,
                        viewModel: viewModel  // Pass the view model here
                    )
                }
                return existingView
            } else {
                let hostingController = UIHostingController(
                    rootView: EmojiPinView(
                        emoji: pin.emoji,
                        showComment: showComment,
                        emojiFontSize: 30,
                        postID: pin.id,
                        upvotes: pin.upvotes,
                        isLiked: pin.isLiked,
                        isNew: pin.isNew,
                        isTrending: pin.isTrending,
                        comment: pin.comment,
                        commentFontSize: 15,
                        isCurrentUserPin: pin.isCurrentUserPin,
                        viewModel: viewModel  // Pass the view model here
                    )
                )
                hostingController.view.backgroundColor = .clear
                let wrapper = HostingViewWrapper(hostingController: hostingController)
                annotationViews[id] = wrapper
                return wrapper
            }
        }
    }
}

// MARK: - A simple UIView that embeds a UIHostingController

class HostingViewWrapper: UIView {
    let hostingController: UIHostingController<EmojiPinView>
    
    init(hostingController: UIHostingController<EmojiPinView>) {
        self.hostingController = hostingController
        super.init(frame: .zero)
        
        addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
