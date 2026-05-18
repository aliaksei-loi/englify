import Testing
@testable import EnglifyKit

@Suite struct FailureClassifierTests {
    @Test func cliMissingTakesPrecedence() {
        #expect(FailureClassifier.classify(exitCode: 127, stderr: "offline", cliMissing: true, timedOut: true) == .cliNotFound)
    }

    @Test func timeoutWinsOverNetworkStderr() {
        #expect(FailureClassifier.classify(exitCode: 124, stderr: "network unreachable", cliMissing: false, timedOut: true) == .timeout)
    }

    @Test func detectsNotAuthenticated() {
        #expect(FailureClassifier.classify(exitCode: 1, stderr: "Error: not authenticated. Please run `claude`.", cliMissing: false, timedOut: false) == .notAuthenticated)
    }

    @Test func detectsOffline() {
        #expect(FailureClassifier.classify(exitCode: 1, stderr: "could not resolve host", cliMissing: false, timedOut: false) == .offline)
    }

    @Test func unknownCarriesStderr() {
        let mode = FailureClassifier.classify(exitCode: 2, stderr: "weird thing\n", cliMissing: false, timedOut: false)
        #expect(mode == .unknown("weird thing"))
    }
}
