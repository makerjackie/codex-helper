import Foundation

enum AutoRetryActivity: Equatable {
    case watching
    case scheduled(attempt: Int, delaySeconds: Int)
    case submitted(attempt: Int)
    case submissionBlocked
    case cancelledForNewActivity
}
