#if !canImport(Combine)
// Linux liest den UI-Zustand über den Desktop-Prozesskanal. Die Speicherung
// bleibt MainActor-isoliert; dort gibt es keine Combine-Abonnenten.
@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

public protocol ObservableObject {}

public struct PollingChangeSignal {
    public init() {}
    public func send() {}
}

extension ObservableObject {
    public var objectWillChange: PollingChangeSignal { PollingChangeSignal() }
}
#endif
