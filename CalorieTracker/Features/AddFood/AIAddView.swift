import PhotosUI
import SwiftUI

/// Describe a meal and/or attach a photo. The estimate runs in the background and shows up on the home screen.
struct AIAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AnalysisCenter.self) private var analysis

    let day: Date

    @State private var description = ""
    @State private var photo: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var error: String?
    @FocusState private var focused: Bool
    private let provider = AIProviderSettings.activeProvider

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What did you eat?")
                            .font(.headline)
                        TextField("e.g. two eggs and toast with butter", text: $description, axis: .vertical)
                            .lineLimit(4...8)
                            .focused($focused)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        if let photo, let image = UIImage(data: photo) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipShape(.rect(cornerRadius: 14))
                                .overlay(alignment: .topTrailing) {
                                    Button("Remove photo", systemImage: "xmark") { self.photo = nil }
                                        .labelStyle(.iconOnly)
                                        .font(.footnote.bold())
                                        .padding(8)
                                        .background(.ultraThinMaterial, in: .circle)
                                        .padding(8)
                                        .tint(.primary)
                                }
                        }
                        HStack(spacing: 10) {
                            if CameraPicker.isAvailable {
                                Button { showingCamera = true } label: {
                                    Label("Camera", systemImage: "camera")
                                }
                                .buttonStyle(.secondary)
                            }
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("Library", systemImage: "photo")
                            }
                            .buttonStyle(.secondary)
                        }
                        Text("A photo of the plate or the nutrition label helps. A description alone works too.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .card()

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .card()
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .pageBackground()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    Button("Analyze", action: start)
                        .buttonStyle(.primary)
                        .disabled(photo == nil && description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("Uses \(provider.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.page)
            }
            .navigationTitle("Describe a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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
            .onAppear { focused = photo == nil }
        }
    }

    private func start() {
        if analysis.start(day: day, description: description, photo: photo) {
            dismiss()
        } else {
            error = "Couldn't read that photo."
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
