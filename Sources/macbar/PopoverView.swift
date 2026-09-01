import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var audio: AudioController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VolumeRow(kind: .output)
            Divider()
            VolumeRow(kind: .input)
        }
        .padding(16)
        .frame(width: 300)
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
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isSilent)) { timeline in
                    Image(systemName: leadingSymbol)
                        .frame(width: 20)
                        .opacity(iconOpacity(at: timeline.date))
                }
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

    private func iconOpacity(at date: Date) -> Double {
        if isSilent { return 0.45 }
        let t = date.timeIntervalSinceReferenceDate * 3.0
        return 0.6 + 0.4 * abs(sin(t))
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