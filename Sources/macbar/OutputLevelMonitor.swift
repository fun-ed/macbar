import CoreAudio
import Foundation

final class OutputLevelMonitor {
    var onLevel: ((Double) -> Void)?
    var onFailed: (() -> Void)?

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var active = false
    private let meter = LevelMeter()

    func start() {
        guard !active else { return }
        guard #available(macOS 14.4, *) else {
            onFailed?()
            return
        }
        do {
            try activate()
            active = true
        } catch {
            stop()
            onFailed?()
        }
    }

    func stop() {
        active = false
        meter.reset()
        if #available(macOS 14.4, *) {
            if let proc = ioProcID, aggregateID != 0 {
                _ = AudioDeviceStop(aggregateID, proc)
                _ = AudioDeviceDestroyIOProcID(aggregateID, proc)
            }
            ioProcID = nil
            if aggregateID != 0 {
                _ = AudioHardwareDestroyAggregateDevice(aggregateID)
                aggregateID = 0
            }
            if tapID != 0 {
                _ = AudioHardwareDestroyProcessTap(tapID)
                tapID = 0
            }
        } else {
            ioProcID = nil
            aggregateID = 0
            tapID = 0
        }
    }

    @available(macOS 14.4, *)
    private func activate() throws {
        let description = CATapDescription()
        description.name = "macbar-level"
        description.uuid = UUID()
        description.isPrivate = true
        description.isExclusive = true
        description.__processes = []
        description.isMixdown = true
        description.isMono = false
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(0)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTapID)
        guard tapStatus == noErr else { throw TapError.creationFailed(tapStatus) }
        tapID = newTapID

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "macbar-level-aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: 1
                ]
            ]
        ]
        var newAggregateID = AudioObjectID(0)
        let aggStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregateID)
        guard aggStatus == noErr else { throw TapError.creationFailed(aggStatus) }
        aggregateID = newAggregateID

        let tapFormat = readTapFormat()
        let meter = self.meter
        var procID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { [weak self] _, inputData, _, _, _ in
            guard let self else { return }
            let raw = Self.level(fromBufferList: inputData, format: tapFormat)
            meter.push(rawLevel: raw) { value in
                DispatchQueue.main.async { self.onLevel?(value) }
            }
        }
        guard procStatus == noErr, procID != nil else { throw TapError.creationFailed(procStatus) }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else { throw TapError.creationFailed(startStatus) }
    }

    private func readTapFormat() -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr else { return nil }
        return format
    }

    private static func level(fromBufferList list: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription?) -> Double {
        let isFloat = format.map { ($0.mFormatFlags & kAudioFormatFlagIsFloat) != 0 } ?? true
        guard isFloat else { return 0 }
        var sum = 0.0
        var count = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer<AudioBufferList>(mutating: list)) {
            guard let data = buffer.mData else { continue }
            let samples = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            guard samples > 0 else { continue }
            let ptr = data.bindMemory(to: Float32.self, capacity: samples)
            var i = 0
            while i < samples {
                let v = Double(ptr[i])
                sum += v * v
                count += 1
                i += 4
            }
        }
        guard count > 0 else { return 0 }
        return LevelMeter.level(fromRMS: (sum / Double(count)).squareRoot())
    }
}

private enum TapError: Error {
    case creationFailed(OSStatus)
}