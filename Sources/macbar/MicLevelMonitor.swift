import AVFoundation
import Foundation

final class MicLevelMonitor {
    var onLevel: ((Double) -> Void)?
    var onPermissionDenied: (() -> Void)?
    var onFailed: (() -> Void)?

    private let engine = AVAudioEngine()
    private let meter = LevelMeter()
    private var tapInstalled = false

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.startEngine() } else { self.onPermissionDenied?() }
                }
            }
        default:
            DispatchQueue.main.async { [weak self] in self?.onPermissionDenied?() }
        }
    }

    func stop() {
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        meter.reset()
    }

    private func startEngine() {
        guard !tapInstalled else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onFailed?()
            return
        }
        let meter = self.meter
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let raw = Self.level(from: buffer)
            meter.push(rawLevel: raw) { value in
                DispatchQueue.main.async { self.onLevel?(value) }
            }
        }
        tapInstalled = true
        do {
            try engine.start()
        } catch {
            stop()
            onFailed?()
        }
    }

    private static func level(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let channels = Int(buffer.format.channelCount)
        var sum = 0.0
        var count = 0
        for channel in 0..<channels {
            let samples = channelData[channel]
            var i = 0
            while i < frames {
                let v = Double(samples[i])
                sum += v * v
                count += 1
                i += 4
            }
        }
        guard count > 0 else { return 0 }
        return LevelMeter.level(fromRMS: (sum / Double(count)).squareRoot())
    }
}