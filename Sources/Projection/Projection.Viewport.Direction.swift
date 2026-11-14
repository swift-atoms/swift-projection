extension Projection.Viewport {
    public enum Direction: String, Hashable, Sendable, CaseIterable {
        /// The image's y grows upward, so a normalised y of 1 lands on its greatest y.
        case up
        /// The image's y grows downward, as a raster's rows do, so a normalised y of 1 lands on its
        /// least y.
        case down
    }
}

#if !hasFeature(Embedded)
    extension Projection.Viewport.Direction: Codable {}
#endif
