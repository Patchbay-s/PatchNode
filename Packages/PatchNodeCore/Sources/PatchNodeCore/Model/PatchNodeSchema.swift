#if canImport(SwiftData)
import Foundation
import SwiftData

/// Version 1 of the SwiftData schema: the one shipped in PatchNode 1.0, which
/// created its store without versioning (`Schema([ServiceConfig.self, …])`).
/// SwiftData matches stores by the shape of their entities, so a store written
/// by 1.0 opens as V1. These copies are frozen: never edit them.
public enum PatchNodeSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [ServiceConfig.self, PromQLFavorite.self, HomeAssistantPin.self]
    }

    @Model
    public final class ServiceConfig {
        @Attribute(.unique) public var id: UUID
        public var kindRawValue: String
        public var name: String
        public var urlString: String

        public init(id: UUID, kindRawValue: String, name: String, urlString: String) {
            self.id = id
            self.kindRawValue = kindRawValue
            self.name = name
            self.urlString = urlString
        }
    }

    @Model
    public final class PromQLFavorite {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var query: String
        public var unitRawValue: String
        public var rangeMinutes: Int
        public var serviceID: UUID
        public var createdAt: Date

        public init(id: UUID, name: String, query: String, unitRawValue: String, rangeMinutes: Int, serviceID: UUID, createdAt: Date) {
            self.id = id
            self.name = name
            self.query = query
            self.unitRawValue = unitRawValue
            self.rangeMinutes = rangeMinutes
            self.serviceID = serviceID
            self.createdAt = createdAt
        }
    }

    @Model
    public final class HomeAssistantPin {
        @Attribute(.unique) public var id: UUID
        public var serviceID: UUID
        public var entityID: String
        public var sortOrder: Int

        public init(id: UUID, serviceID: UUID, entityID: String, sortOrder: Int) {
            self.id = id
            self.serviceID = serviceID
            self.entityID = entityID
            self.sortOrder = sortOrder
        }
    }
}

/// Version 2 (PatchNode 1.1): compatible with CloudKit, for the optional iCloud
/// sync. No unique attribute, a default value for every attribute, and
/// `SyncedSetting` for the tabs and dashboard order. Frozen copies of the
/// classes as 1.1 shipped them: never edit them.
public enum PatchNodeSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [ServiceConfig.self, PromQLFavorite.self, HomeAssistantPin.self, SyncedSetting.self]
    }

    @Model
    public final class ServiceConfig {
        public var id: UUID = UUID()
        public var kindRawValue: String = ServiceKind.proxmoxVE.rawValue
        public var name: String = ""
        public var urlString: String = ""

        public init(id: UUID, kindRawValue: String, name: String, urlString: String) {
            self.id = id
            self.kindRawValue = kindRawValue
            self.name = name
            self.urlString = urlString
        }
    }

    @Model
    public final class PromQLFavorite {
        public var id: UUID = UUID()
        public var name: String = ""
        public var query: String = ""
        public var unitRawValue: String = PromQLUnit.none.rawValue
        public var rangeMinutes: Int = 60
        public var serviceID: UUID = UUID()
        public var createdAt: Date = Date.distantPast

        public init(id: UUID, name: String, query: String, unitRawValue: String, rangeMinutes: Int, serviceID: UUID, createdAt: Date) {
            self.id = id
            self.name = name
            self.query = query
            self.unitRawValue = unitRawValue
            self.rangeMinutes = rangeMinutes
            self.serviceID = serviceID
            self.createdAt = createdAt
        }
    }

    @Model
    public final class HomeAssistantPin {
        public var id: UUID = UUID()
        public var serviceID: UUID = UUID()
        public var entityID: String = ""
        public var sortOrder: Int = 0

        public init(id: UUID, serviceID: UUID, entityID: String, sortOrder: Int) {
            self.id = id
            self.serviceID = serviceID
            self.entityID = entityID
            self.sortOrder = sortOrder
        }
    }

    @Model
    public final class SyncedSetting {
        public var key: String = ""
        public var value: String = ""
        public var updatedAt: Date = Date.distantPast

        public init(key: String, value: String, updatedAt: Date) {
            self.key = key
            self.value = value
            self.updatedAt = updatedAt
        }
    }
}

/// Version 3 (PatchNode 1.2): adds `SSHHost`; nothing else changes. The current
/// classes (`ServiceConfig`…) are this version.
///
/// Changing a model again (adding, renaming, retyping or removing a property):
/// 1. copy the current classes, as they are today, inside a frozen
///    `PatchNodeSchemaV3` like V2 above;
/// 2. add `PatchNodeSchemaV4` (version 4.0.0) listing the new classes;
/// 3. append it to `PatchNodeMigrationPlan.schemas` with a stage V3 → V4
///    (`.lightweight` when SwiftData can infer it, `.custom` otherwise). With
///    CloudKit, only add attributes or entities (optional or with a default):
///    a synced schema can't rename or remove them;
/// 4. point `PatchNodeModelStore.schema` at V4, and update the fingerprint in
///    `SchemaMigrationTests` alongside a test that opens a V3 store.
/// `SchemaMigrationTests.currentModelsMatchV3` fails if a model changes
/// without this.
public enum PatchNodeSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            PatchNodeCore.ServiceConfig.self, PatchNodeCore.PromQLFavorite.self, PatchNodeCore.HomeAssistantPin.self,
            PatchNodeCore.SyncedSetting.self, SSHHost.self,
        ]
    }
}

/// Every schema the app has shipped, oldest first, and how to go from one to the
/// next. A store is never deleted or recreated: a missing stage makes opening
/// fail (the app then shows its store error screen) rather than lose the
/// configured services.
public enum PatchNodeMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [PatchNodeSchemaV1.self, PatchNodeSchemaV2.self, PatchNodeSchemaV3.self]
    }

    /// V1 → V2 only drops the unique constraints, adds default values and a new
    /// entity; V2 → V3 adds an entity. Core Data infers both, every record is
    /// kept as is.
    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: PatchNodeSchemaV1.self, toVersion: PatchNodeSchemaV2.self),
            .lightweight(fromVersion: PatchNodeSchemaV2.self, toVersion: PatchNodeSchemaV3.self),
        ]
    }
}

/// The one way the app, its background refresh and its App Intents open the
/// store: current schema plus the migration plan.
public enum PatchNodeModelStore {
    /// The schema the running version writes.
    public static var schema: Schema {
        Schema(versionedSchema: PatchNodeSchemaV3.self)
    }

    public static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: PatchNodeMigrationPlan.self, configurations: [configuration])
    }
}
#endif
