import Combine
import Foundation

final class PopupViewModel: ObservableObject {
    @Published var sourceText = ""
    @Published var output = ""
    @Published var isTranslating = false
    @Published var errorMessage: String?

    private let service: TranslationService
    private var task: Task<Void, Never>?

    init(service: TranslationService) {
        self.service = service
    }

    func translate() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        task?.cancel()
        output = ""
        errorMessage = nil
        isTranslating = true

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.service.stream(text: text) { [weak self] partial in
                    self?.output = partial
                }
                self.isTranslating = false
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isTranslating = false
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        isTranslating = false
    }
}

