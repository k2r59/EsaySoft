import SwiftUI

struct RecordingSetupView: View {
    @State private var options = RecordingOptions()
    @State private var cameras: [RecordingDevice] = []
    @State private var microphones: [RecordingDevice] = []
    let cancel: () -> Void
    let start: (RecordingOptions) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "record.circle").font(.system(size: 25)).foregroundStyle(Theme.mint).frame(width: 52, height: 52).background(Theme.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
                Text("Enregistrer une vidéo").font(.system(size: 23, weight: .semibold))
            }
            Picker("À enregistrer", selection: $options.area) { Text("Sélectionner une zone").tag(true); Text("Écran entier").tag(false) }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 14) {
                PreferenceToggle("Microphone", isOn: $options.microphone)
                if options.microphone { devicePicker("Microphone", selection: $options.microphoneID, devices: microphones) }
                Divider().opacity(0.3)
                PreferenceToggle("Webcam en incrustation", isOn: $options.webcam)
                if options.webcam {
                    devicePicker("Webcam", selection: $options.cameraID, devices: cameras)
                    Text("Position réglable pendant l’enregistrement.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Divider().opacity(0.3)
                PreferenceToggle("Son de l’ordinateur", isOn: $options.systemAudio)
            }.toggleStyle(.switch).font(.system(size: 13)).padding(20).surface()
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("Qualité vidéo").font(.system(size: 13, weight: .medium)); Text("30 images/s · MP4").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                Spacer()
                Picker("Qualité vidéo", selection: $options.fullResolution) { Text("Native · jusqu’à 4K").tag(true); Text("Légère · 1080p").tag(false) }.labelsHidden().frame(width: 210)
            }
            Label("Arrêter : barre flottante ou ⌃⌥⌘S", systemImage: "stop.circle").font(.system(size: 11)).foregroundStyle(Theme.muted)
            HStack { Button("Annuler", action: cancel).buttonStyle(PasteButtonStyle()).keyboardShortcut(.cancelAction); Spacer(); Button(options.area ? "Choisir la zone" : "Démarrer dans 3 s") { start(options) }.buttonStyle(PasteButtonStyle(primary: true)).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 500).chromeSurface(radius: 22).foregroundStyle(Theme.ink)
        .task { cameras = RecordingDevice.cameras; microphones = RecordingDevice.microphones }
    }
    private func devicePicker(_ title: String, selection: Binding<String>, devices: [RecordingDevice]) -> some View {
        HStack {
            Text("Source").foregroundStyle(Theme.muted)
            Spacer()
            Picker(title, selection: selection) { Text("Par défaut").tag(""); ForEach(devices) { device in Text(device.name).tag(device.id) } }.labelsHidden().frame(width: 280)
        }.font(.system(size: 11))
    }
}
