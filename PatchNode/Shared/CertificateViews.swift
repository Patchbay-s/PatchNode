import SwiftUI
import PatchNodeCore

/// Dashboard: services whose TLS certificate expires within 14 days (orange),
/// or 7 days (red). Hidden when there is none.
struct CertificatesBanner: View {
    let services: [ServiceDescriptor]
    /// Changes after each refresh, so the banner is evaluated again (the registry
    /// filled during connections isn't observable).
    let refreshStamp: [Date?]

    var body: some View {
        let now = Date.now
        let expiring = CertificateRegistry.shared.attention(among: services, now: now, kind: \.kind, url: \.url)
        if !expiring.isEmpty {
            let critical = expiring.contains { $0.expiry.level(now: now) == .critical }
            let tint: Color = critical ? .red : .orange
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Certificates expiring soon").font(.headline)
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark").foregroundStyle(tint)
                }
                ForEach(expiring, id: \.item.id) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: entry.item.name)
                        Spacer()
                        CertificateExpiryText(expiry: entry.expiry, now: now)
                            .foregroundStyle(entry.expiry.level(now: now) == .critical ? Color.red : Color.orange)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
                Text("Renew them on your reverse proxy: once expired, the service becomes unreachable from PatchNode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(tint.opacity(0.12), in: .rect(cornerRadius: 16))
        }
    }
}

/// "Expires in 9 days", "Expires today" or "Expired".
struct CertificateExpiryText: View {
    let expiry: CertificateExpiry
    let now: Date

    var body: some View {
        let days = expiry.daysRemaining(now: now)
        if expiry.notAfter <= now {
            Text("Expired")
        } else if days == 0 {
            Text("Expires today")
        } else {
            Text("Expires in \(days) days")
        }
    }
}

/// Diagnostics: the certificate seen for one service.
struct CertificateDiagnosticLine: View {
    let service: ServiceDescriptor

    private static func color(for level: HealthLevel) -> Color {
        switch level {
        case .ok: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }

    var body: some View {
        if service.kind.hasOwnCertificate {
            let now = Date.now
            if let expiry = CertificateRegistry.shared.expiry(for: service.url, now: now) {
                HStack(spacing: 4) {
                    Text("Certificate valid until \(expiry.notAfter, format: .dateTime.day().month().year())")
                    Text(verbatim: "·")
                    CertificateExpiryText(expiry: expiry, now: now)
                }
                .font(.caption)
                .foregroundStyle(Self.color(for: expiry.level(now: now)))
            } else {
                Text("Certificate not seen yet: read at the next new connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
