import Foundation

/// Public pages and support channels of the app (the publisher's, not tied to
/// any installation). A nil value hides the button or link that needs it.
enum AppLinks {
    /// Web privacy policy (also readable offline in Settings › About).
    static let privacyPolicy: URL? = URL(string: "https://patchbay-s.github.io/PatchNode/privacy.html")
    /// Web support page.
    static let support: URL? = URL(string: "https://patchbay-s.github.io/PatchNode/support.html")
    /// Direct e-mail support is disabled until a non-personal address is configured.
    static let supportEmail: String? = nil
    /// Optional WhatsApp link (https://wa.me/…); hidden when nil.
    static let whatsAppURL: URL? = nil
}
