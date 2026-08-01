import SwiftUI

/// Reading and camera settings for the live prompter. Script settings always
/// apply; the camera sections appear only when the camera is on, and each
/// individual camera row is conditional on `camera.capabilities` — what's shown
/// reflects what this specific iPhone's front camera actually supports.
struct PrompterControlsSheet: View {
    @ObservedObject var camera: CameraController
    @ObservedObject var state: TeleprompterState
    @Environment(\.dismiss) private var dismiss

    private var hasAnyCameraCapability: Bool {
        camera.capabilities.maxZoom > camera.capabilities.minZoom + 0.05
            || camera.capabilities.qualityTiers.count > 1
            || (camera.selectedTier?.frameRates.count ?? 0) > 1
            || camera.capabilities.supportsHDR
            || camera.capabilities.supportsStabilization
            || camera.capabilities.supportsLowLightBoost
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading line") {
                    HStack {
                        Text("\(Int(state.cueLineFraction * 100))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .leading)
                        Slider(value: $state.cueLineFraction, in: 0.08...0.6)
                    }
                    Text("How far down the screen you read. Keep it high so your eyes stay near the camera lens.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Text size") {
                    HStack {
                        Text("\(Int(state.fontSize))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .leading)
                        Slider(value: $state.fontSize, in: 20...64, step: 1)
                    }
                }

                Section("Timing") {
                    Toggle("Show timing", isOn: $state.showTiming)
                    Picker("Countdown", selection: $state.countdownSeconds) {
                        ForEach(TeleprompterState.countdownOptions, id: \.self) { seconds in
                            Text(seconds == 0 ? "Off" : "\(seconds)s").tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("\(Int(state.targetWPM)) wpm")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $state.targetWPM, in: ReadingPace.wpmRange, step: 5)
                    }
                    Text("Your target pace, used for the estimate until you've read enough of the take for Cue to measure your real one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if state.cameraEnabled {
                    Section("Contrast over camera") {
                        HStack {
                            Text("Text")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .leading)
                            Slider(value: $state.textOpacity, in: 0.3...1.0)
                        }
                        HStack {
                            Text("Dim")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .leading)
                            Slider(value: $state.cameraDimming, in: 0.0...0.85)
                        }
                        Text("Raise Dim to darken the camera behind the words. Lower Text to see more of yourself through them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if state.cameraEnabled && camera.capabilities.maxZoom > camera.capabilities.minZoom + 0.05 {
                    Section("Zoom") {
                        HStack {
                            Text("\(camera.zoomFactor, specifier: "%.1f")×")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { camera.zoomFactor },
                                    set: { camera.setZoom($0) }
                                ),
                                in: camera.capabilities.minZoom...camera.capabilities.maxZoom
                            )
                        }
                    }
                }

                if state.cameraEnabled, let mode = camera.selectedMode, let tier = camera.selectedTier {
                    // Two short segmented toggles instead of an exhaustive
                    // format list — the same choice Camera.app offers, and the
                    // same one mirrored on the prompter itself.
                    Section("Video quality") {
                        if camera.capabilities.qualityTiers.count > 1 {
                            Picker("Size", selection: Binding(
                                get: { tier },
                                set: { camera.selectTier($0) }
                            )) {
                                ForEach(camera.capabilities.qualityTiers) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        if tier.frameRates.count > 1 {
                            Picker("Frame rate", selection: Binding(
                                get: { mode.frameRate },
                                set: { camera.apply(VideoMode(height: tier.height, frameRate: $0)) }
                            )) {
                                ForEach(tier.frameRates, id: \.self) { rate in
                                    Text("\(Int(rate)) fps").tag(rate)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        if camera.isRecording {
                            Text("Stop recording to change quality.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if state.cameraEnabled && (camera.capabilities.supportsHDR || camera.capabilities.supportsStabilization || camera.capabilities.supportsLowLightBoost) {
                    Section("Capture") {
                        if camera.capabilities.supportsHDR {
                            Toggle("HDR video", isOn: Binding(
                                get: { camera.hdrEnabled },
                                set: { camera.setHDR($0) }
                            ))
                        }
                        if camera.capabilities.supportsStabilization {
                            Toggle("Stabilization", isOn: Binding(
                                get: { camera.stabilizationEnabled },
                                set: { camera.setStabilization($0) }
                            ))
                        }
                        if camera.capabilities.supportsLowLightBoost {
                            Toggle("Low-light boost", isOn: Binding(
                                get: { camera.lowLightBoostEnabled },
                                set: { camera.setLowLightBoost($0) }
                            ))
                        }
                    }
                }

                if state.cameraEnabled && !hasAnyCameraCapability {
                    Section {
                        Text("This iPhone's front camera doesn't expose any adjustable capture options — it'll record at its default settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Prompter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
