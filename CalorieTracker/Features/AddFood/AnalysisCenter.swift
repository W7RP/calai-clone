import Foundation
import Observation

/// Photo and text estimates run here, off the add screens, so the camera can close straight away and the
/// meal shows up on the home screen as an "Analyzing" card until it's ready to review.
@MainActor
@Observable
final class AnalysisCenter {
    enum State: Equatable {
        case working
        case ready(FoodEstimate)
        case failed(String)
    }

    struct Job: Identifiable, Equatable {
        let id = UUID()
        let day: Date
        let description: String
        let jpeg: Data?
        /// Small copy of the photo for the card and, once saved, the log entry.
        let thumbnail: Data?
        let started = Date.now
        var state = State.working

        var title: String {
            let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Your meal" : text
        }
    }

    private(set) var jobs: [Job] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]

    /// Starts an estimate. Returns false (and starts nothing) if the photo can't be read.
    @discardableResult
    func start(day: Date, description: String, photo: Data?) -> Bool {
        let jpeg = photo.flatMap { ImagePreparation.jpegForUpload($0) }
        if photo != nil, jpeg == nil { return false }
        let thumbnail = jpeg.flatMap { ImagePreparation.jpegForUpload($0, maxSide: 240, quality: 0.6) }
        let job = Job(day: day, description: description, jpeg: jpeg, thumbnail: thumbnail)
        jobs.insert(job, at: 0)
        run(job.id)
        return true
    }

    func retry(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .working
        run(id)
    }

    func remove(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        jobs.removeAll { $0.id == id }
    }

    func job(_ id: UUID) -> Job? { jobs.first { $0.id == id } }

    private func run(_ id: UUID) {
        guard let job = job(id) else { return }
        let description = job.description
        let jpeg = job.jpeg
        tasks[id] = Task { [weak self] in
            let state: State
            do {
                let estimate = try await FoodEstimator.current().estimate(description: description, jpeg: jpeg)
                state = .ready(estimate)
            } catch is CancellationError {
                return
            } catch {
                state = .failed(error.localizedDescription)
            }
            self?.finish(id, state: state)
        }
    }

    private func finish(_ id: UUID, state: State) {
        tasks[id] = nil
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state
    }
}
