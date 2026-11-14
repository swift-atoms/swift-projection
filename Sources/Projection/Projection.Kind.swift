extension Projection {
    @frozen
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case perspective
        case orthographic
    }
}

#if !hasFeature(Embedded)
    extension Projection.Kind: Codable {}
#endif
