import Foundation

/// Container actions (`POST /containers/{id}/{action}`). A socket proxy with
/// POST=0 answers 403: actions are disabled on that service.
public enum DockerContainerAction: String, Sendable, Hashable, CaseIterable {
    case start
    case stop
    case restart
}

public enum DockerActionOutcome: Sendable, Hashable {
    /// 204: done.
    case done
    /// 304: the container was already in the requested state.
    case alreadyInState
}
