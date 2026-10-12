import SwiftUI

struct ApplicationsVolumeView: View {
    @EnvironmentObject private var apps: AppAudioController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applications").font(.headline)
            if !apps.supported {
                Text("Per-application volume requires macOS 14.4 or later.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if let error = apps.discoveryError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if apps.applications.isEmpty {
                    Text("No applications are playing audio.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(apps.applications) { row in
                                ApplicationVolumeRow(row: row)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(height: min(280, CGFloat(apps.applications.count) * 112))
                }
            }
        }
    }
}

private struct ApplicationVolumeRow: View {
    @EnvironmentObject private var apps: AppAudioController
    let row: AppAudioRowState

    private var applied: Bool { row.status == .active }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(row.group.name).font(.callout.weight(.medium)).lineLimit(1)
                    .help(row.group.appPath ?? row.group.name)
                Spacer()
                Text("\(Int((row.gain.volume * 100).rounded()))%")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Slider(value: Binding(get: { row.gain.volume }, set: { apps.setVolume(row.id, $0) }), in: 0...1)
                    .accessibilityLabel("\(row.group.name) volume")
                Button { apps.toggleMute(row.id) } label: {
                    Image(systemName: applied && row.gain.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 22)
                        .foregroundStyle(applied && row.gain.muted ? Color.red : Color.primary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Toggle \(row.group.name) mute")
            }
            HStack(alignment: .top, spacing: 4) {
                Text(statusText).font(.caption).foregroundStyle(isError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isError {
                    Button("Retry") { apps.retry(row.id) }.font(.caption).buttonStyle(.borderless)
                }
            }
        }
    }

    private var isError: Bool {
        if case .failed = row.status { return true }
        return false
    }

    private var statusText: String {
        switch row.status {
        case .original: return "Original output"
        case .checking: return "Checking audio access… Requested setting not yet verified."
        case .active: return row.gain.muted ? "Muted" : "Application volume applied"
        case .waiting: return "Waiting for audio. Requested setting not applied."
        case .failed(let error): return "Not applied. \(error)"
        }
    }
}
