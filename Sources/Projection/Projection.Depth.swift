extension Projection {
    public enum Depth: String, Hashable, Sendable, CaseIterable {
        case symmetric
        case unit
    }
}

extension Projection.Depth {
    public var range: ClosedRange<Scalar> {
        switch self {
        case .symmetric: -1...1
        case .unit: 0...1
        }
    }
}

#if !hasFeature(Embedded)
    extension Projection.Depth: Codable {}
#endif
