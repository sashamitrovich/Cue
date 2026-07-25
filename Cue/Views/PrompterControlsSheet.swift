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
            || camera.capabilities.resolutionOptions.count > 1
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

                if state.cameraEnabled && camera.capabilities.resolutionOptions.count > 1 {
                    Section("Resolution") {
                        Picker("Resolution", selection: Binding(
                            get: { camera.selectedResolution },
                            set: { if let option = $0 { camera.applyResolution(option) } }
                        )) {
                            ForEach(camera.capabilities.resolutionOptions) { option in
                                Text(option.label).tag(Optional(option))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
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
