import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var audio: AudioController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VolumeRow(kind: .output)
            Divider()
            VolumeRow(kind: .input)
            Divider()
            ApplicationsVolumeView()
        }
        .padding(16)
        .frame(width: 300, height: 520, alignment: .top)
    }
}

struct VolumeLevelBar: View {
    @EnvironmentObject private var audio: AudioController
    let kind: VolumeKind

    private var metering: Bool {
        audio.isMetering(kind)
    }

    private var fraction: Double {
        guard audio.isAvailable(kind), audio.hasVolumeControl(kind) else { return 0 }
        return metering ? audio.level(for: kind) : Double(audio.volume(for: kind))
    }

    var body: some View {
        GeometryReader { geo in
            let fillWidth = fraction > 0.001 ? max(3, geo.size.width * fraction) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(fillGradient)
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 6)
        .animation(metering ? nil : .spring(response: 0.35), value: fraction)
        .accessibilityHidden(true)
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: kind == .output
                ? [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.35, green: 0.85, blue: 1.0)]
                : [Color(red: 0.6, green: 0.35, blue: 1.0), Color(red: 0.85, green: 0.45, blue: 1.0)],
            startPoint: .leading, endPoint: .trailing)
    }
}

extension View {
    @ViewBuilder
    func symbolBounce<V: Equatable>(value: V) -> some View {
        if #available(macOS 14.0, *) {
            symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }
}

struct VolumeRow: View {
    @EnvironmentObject var audio: AudioController
    let kind: VolumeKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: leadingSymbol)
                    .frame(width: 20)
                    .opacity(isSilent ? 0.45 : 1.0)
                Text(kind == .output ? "Speaker" : "Microphone")
                    .font(.headline)
                Spacer()
                Text(percentText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Slider(value: volumeBinding)
                    .disabled(!audio.hasVolumeControl(kind))
                Button(action: { audio.toggleMute(kind) }) {
                    Image(systemName: muteSymbol)
                        .frame(width: 22)
                        .foregroundStyle(audio.isMuted(kind) ? Color.red : Color.primary)
                        .symbolBounce(value: audio.isMuted(kind))
                }
                .buttonStyle(.borderless)
                .disabled(!audio.isAvailable(kind))
            }
            VolumeLevelBar(kind: kind)
        }
        .disabled(!audio.isAvailable(kind))
    }

    private var volumeBinding: Binding<Float> {
        Binding(
            get: { audio.volume(for: kind) },
            set: { audio.setVolume(kind, $0) }
        )
    }

    private var percentText: String {
        guard audio.isAvailable(kind) else { return "N/A" }
        guard audio.hasVolumeControl(kind) else { return "Fixed" }
        let v = audio.volume(for: kind)
        return "\(Int((v * 100).rounded()))%"
    }

    private var muted: Bool {
        audio.isMuted(kind)
    }

    private var isSilent: Bool {
        audio.isMuted(kind) || (audio.hasVolumeControl(kind) && audio.volume(for: kind) < 0.005)
    }

    private var leadingSymbol: String {
        switch kind {
        case .output:
            return isSilent ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .input:
            return isSilent ? "mic.slash.fill" : "mic.fill"
        }
    }

    private var muteSymbol: String {
        switch kind {
        case .output:
            return muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .input:
            return muted ? "mic.slash.fill" : "mic.fill"
        }
    }
}