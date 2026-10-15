import Foundation
import PatchNodeCore
import TailscaleKit

typealias TailscaleStore = ServiceStore<TailscaleServiceSnapshot, TailscaleInventory>

extension ServiceStore where Snapshot == TailscaleServiceSnapshot, Inventory == TailscaleInventory {
    /// The OAuth access token lives in `tokenCache` (memory only) until it expires,
    /// and is dropped as soon as the app goes to the background.
    static func tailscale(secretStore: any SecretStore, tokenCache: AccessTokenCache = AccessTokenCache()) -> TailscaleStore {
        TailscaleStore(
            secretStore: secretStore,
            fetch: { service, credential, httpClient in
                // Always the public API, whatever URL was stored: the client secret
                // can't be sent anywhere else. The demo tailnet stays on the device.
                let baseURL = DemoServer.isDemo(service.url) ? service.url : TailscaleClient.defaultBaseURL
                let client = TailscaleClient(
                    baseURL: baseURL, serviceID: service.id, credential: credential,
                    tokenCache: tokenCache, httpClient: httpClient
                )
                return TailscaleServiceSnapshot(serviceID: service.id, serviceName: service.name, devices: try await client.devices())
            },
            makeInventory: { TailscaleInventory(snapshots: $0) },
            level: { inventory, failed, total in inventory.overview.level(failedServices: failed, totalServices: total) },
            onEnterBackground: { await tokenCache.removeAll() }
        )
    }
}
