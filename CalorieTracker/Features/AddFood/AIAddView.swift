import PhotosUI
import SwiftUI

/// Describe a meal and/or attach a photo; the chosen AI provider proposes items, which are reviewed before saving.
struct AIAddView: View {
    @Environment(\.dismiss) private var dismiss

    let day: Date
    var startWithCamera = false

    @State private var description = ""
    @State private var photo: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var isWorking = false
    @State private var error: String?
    @State private var estimate: FoodEstimate?
    @State private var didAutoOpenCamera = false
    @State private var provider = AIProviderSettings.activeProvider

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. two eggs and toast with butter", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("What did you eat?")
                } footer: {
                    Text("Add a photo of the plate or the nutrition label, a description, or both.")
                }

                Section("Photo") {
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(.rect(cornerRadius: 8))
                        Button("Remove photo", role: .destructive) { self.photo = nil }
                    }
                    if CameraPicker.isAvailable {
                        Button("Take photo", systemImage: "camera") { showingCamera = true }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose from library", systemImage: "photo")
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Log with \(provider.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Estimate") { Task { await run() } }
                        .disabled(isWorking || (photo == nil && description.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
            .overlay {
                if isWorking {
                    ProgressView("Asking \(provider.name)…")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .navigationDestination(item: $estimate) { estimate in
                ReviewView(estimate: estimate, day: day) { dismiss() }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in
                    if let data { photo = data }
                    showingCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    photo = try? await item.loadTransferable(type: Data.self)
                    photoItem = nil
                }
            }
            .onAppear {
                if startWithCamera, !didAutoOpenCamera, CameraPicker.isAvailable {
                    didAutoOpenCamera = true
                    showingCamera = true
                }
            }
        }
    }

    private func run() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let jpeg = photo.flatMap { ImagePreparation.jpegForUpload($0) }
            if photo != nil, jpeg == nil {
                error = "Couldn't read that photo."
                return
            }
            estimate = try await FoodEstimator.current().estimate(description: description, jpeg: jpeg)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension FoodEstimate: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(items.count)
        hasher.combine(note)
        hasher.combine(analysis)
        for item in items { hasher.combine(item.name) }
    }
}
