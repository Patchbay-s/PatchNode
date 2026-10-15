#if canImport(SwiftData)
import Foundation
import SwiftData

/// A setting that follows the configuration to the user's other devices (tabs,
/// dashboard order: `CloudReconciliation.syncedKeys`). UserDefaults stays the
/// source the screens read; this record only carries the value through iCloud.
/// Never a secret. Several records per key can meet after a sync: the latest wins.
@Model
public final class SyncedSetting {
    public var key: String = ""
    public var value: String = ""
    public var updatedAt: Date = Date.distantPast

    public init(key: String, value: String, updatedAt: Date = .now) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }

    public var snapshot: SyncedSettingValue {
        SyncedSettingValue(key: key, value: value, updatedAt: updatedAt)
    }
}
#endif
