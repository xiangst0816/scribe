import Foundation

protocol SpeechProvider: AnyObject {
    var onAudioLevel: ((Float) -> Void)? { get set }
    var onFinalResult: ((String) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }

    var isReady: Bool { get }

    func start()
    func stop()
    func cancel()
}
