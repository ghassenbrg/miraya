import Foundation

/// Named milestones, not a fabricated percentage or a timer-based success.
public enum ConnectionStep: String {
    case contactingTV, verifyingTV, savingPairing, checkingCapture, preparingTV, preparingMedia, negotiatingMedia, startingCapture, waitingForPicture
    public var title: String {
        switch self {
        case .contactingTV: return "Connecting to your TV…"
        case .verifyingTV: return "Verifying the secure connection…"
        case .savingPairing: return "Saving the verified TV…"
        case .checkingCapture: return "Checking screen access…"
        case .preparingTV: return "Preparing the TV…"
        case .preparingMedia: return "Preparing video and audio…"
        case .negotiatingMedia: return "Establishing the video connection…"
        case .startingCapture: return "Starting your screen capture…"
        case .waitingForPicture: return "Waiting for the first picture on TV…"
        }
    }
    public var detail: String {
        switch self {
        case .contactingTV: return "Your request was received. Contacting Miraya on the selected TV."
        case .verifyingTV: return "Checking the TV identity and your saved authorization."
        case .savingPairing: return "The TV accepted the connection. Saving its pairing securely; approve a macOS Keychain prompt if shown."
        case .checkingCapture: return "Allow screen recording in the macOS prompt if it appears."
        case .preparingTV: return "The TV is getting its player ready."
        case .preparingMedia: return "Starting the local video encoder and system-audio connection."
        case .negotiatingMedia: return "Finding a direct encrypted path across your local network."
        case .startingCapture: return "Opening the selected Mac display."
        case .waitingForPicture: return "Video is starting. Sharing is confirmed when the TV presents a frame."
        }
    }
}
