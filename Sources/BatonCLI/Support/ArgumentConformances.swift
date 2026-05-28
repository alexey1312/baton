import ArgumentParser
import BatonKit

/// `AgentKind` lives in BatonKit (which has no ArgumentParser dependency), so the
/// ExpressibleByArgument conformance is added here, in the CLI layer.
extension AgentKind: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}
