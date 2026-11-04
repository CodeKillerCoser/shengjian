import Foundation

// Owns the guide window lifecycle; permission state never owns a window.
@MainActor final class AuthorizationGuideController {
    private let permissions: PermissionModel
    private var guide: AuthorizationGuide?
    private var request = UUID()

    init(permissions: PermissionModel) { self.permissions = permissions }
    func show() {
        close()
        permissions.open("Privacy_Accessibility")
        let current = request
        Task { [self] in
            await permissions.refreshAccessibility()
            guard current == request, permissions.accessibility == .notGranted else { return }
            let guide = AuthorizationGuide(permissions: permissions, onClose: { [weak self] in self?.close() })
            self.guide = guide
            guide.show()
        }
    }
    func close() {
        request = UUID()
        guide?.close()
        guide = nil
    }
}
