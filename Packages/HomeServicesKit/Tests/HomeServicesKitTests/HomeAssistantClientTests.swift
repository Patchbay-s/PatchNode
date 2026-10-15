import Foundation
import Testing
import PatchNodeCore
@testable import HomeServicesKit

@Suite("HomeAssistantClient")
struct HomeAssistantClientTests {
    private func client(_ fake: FakeHTTPClient, baseURL: URL = Fixtures.homeAssistantURL) -> HomeAssistantClient {
        HomeAssistantClient(baseURL: baseURL, token: Fixtures.haToken, httpClient: fake)
    }

    private static let failures: [(FakeHTTPClient.Outcome, ServiceProviderError)] = [
        (.unauthorized, .unauthorized),
        (.forbidden, .forbidden),
        (.timeout, .unreachable),
        (.serverError, .unexpectedStatus(500)),
        (.invalidJSON, .decodingFailed),
        (.emptyBody, .decodingFailed),
    ]

    // MARK: checkConnection

    @Test func checkConnectionHitsApiWithTrailingSlashAndBearer() async throws {
        let fake = FakeHTTPClient.json(Fixtures.apiRunning)
        try await client(fake).checkConnection()
        let specs = await fake.receivedSpecs
        #expect(specs.count == 1)
        #expect(specs.first?.method == .get)
        #expect(specs.first?.url.absoluteString == "https://ha.example.invalid/api/")
        #expect(specs.first?.headers["Authorization"] == "Bearer \(Fixtures.haToken)")
        #expect(specs.first?.body == nil)
    }

    @Test func checkConnectionKeepsTrailingSlashUnderASubpath() async throws {
        let fake = FakeHTTPClient.json(Fixtures.apiRunning)
        try await client(fake, baseURL: URL(string: "https://proxy.example.invalid/homeassistant/")!).checkConnection()
        #expect(await fake.receivedURLs.first?.absoluteString == "https://proxy.example.invalid/homeassistant/api/")
    }

    @Test func checkConnectionFailuresMapToProviderErrorsWithoutRetry() async throws {
        for (outcome, expected) in Self.failures {
            let fake = FakeHTTPClient(outcome)
            await #expect(throws: expected) { try await client(fake).checkConnection() }
            #expect(await fake.receivedSpecs.count == 1)
        }
    }

    @Test func checkConnectionRejectsANonObjectBody() async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) {
            try await client(FakeHTTPClient.json(#"["API running."]"#)).checkConnection()
        }
    }

    @Test func loggedRequestNeverContainsTheToken() async throws {
        let fake = FakeHTTPClient.json(Fixtures.apiRunning)
        try await client(fake).checkConnection()
        try await client(fake).activate(entityID: "scene.movie_night")
        let specs = await fake.receivedSpecs
        #expect(specs.count == 2)
        for spec in specs {
            #expect(!spec.redactedDescription.contains(Fixtures.haToken))
            #expect(spec.redactedDescription.contains("Authorization: <redacted>"))
        }
    }

    // MARK: states

    @Test func statesDecodesRealisticPayloadAndDropsInvalidEntities() async throws {
        let fake = FakeHTTPClient(routes: ["/api/states": .json(Fixtures.states)])
        let entities = try await client(fake).states()
        #expect(await fake.receivedPaths == ["/api/states"])
        #expect(await fake.receivedSpecs.first?.headers["Authorization"] == "Bearer \(Fixtures.haToken)")
        #expect(entities.map(\.id) == [
            "sensor.living_room_temperature", "scene.movie_night", "script.good_morning",
            "light.living_room", "sensor.garage_door_battery", "sensor.power_meter",
        ])

        let temperature = try #require(entities.first { $0.id == "sensor.living_room_temperature" })
        #expect(temperature.name == "Living room temperature")
        #expect(temperature.state == "21.5")
        #expect(temperature.unit == "°C")
        #expect(temperature.deviceClass == "temperature")
        #expect(temperature.displayState == "21.5 °C")
        let changed = try #require(temperature.lastChanged)
        #expect(abs(changed.timeIntervalSince1970 - 1_714_557_492.345678) < 0.001)

        let script = try #require(entities.first { $0.id == "script.good_morning" })
        // 06:00+02:00 = 04:00Z.
        #expect(script.lastChanged == Date(timeIntervalSince1970: 1_714_536_000))
        #expect(script.unit == nil)
        #expect(script.deviceClass == nil)
        #expect(script.displayState == "off")

        let garage = try #require(entities.first { $0.id == "sensor.garage_door_battery" })
        #expect(garage.name == "sensor.garage_door_battery", "empty friendly_name falls back to the ID")
        #expect(garage.unit == nil, "empty unit is dropped")
        #expect(garage.lastChanged == nil)
        #expect(garage.isUnavailable)
        #expect(garage.displayState == "unavailable")

        let power = try #require(entities.first { $0.id == "sensor.power_meter" })
        #expect(power.name == "sensor.power_meter", "missing friendly_name falls back to the ID")
        #expect(power.state == "1234", "numeric state is read as a string")
        #expect(power.displayState == "1234 W")
        #expect(power.lastChanged == Date(timeIntervalSince1970: 1_714_557_540))
    }

    @Test func statesFailuresMapToProviderErrorsWithoutRetry() async throws {
        for (outcome, expected) in Self.failures {
            let fake = FakeHTTPClient(outcome)
            await #expect(throws: expected) { try await client(fake).states() }
            #expect(await fake.receivedSpecs.count == 1)
        }
    }

    @Test func statesRejectsAnObjectInsteadOfAList() async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) {
            try await client(FakeHTTPClient.json(Fixtures.apiRunning)).states()
        }
    }

    @Test func statesAcceptsAnEmptyList() async throws {
        #expect(try await client(FakeHTTPClient.json("[]")).states().isEmpty)
    }

    // MARK: activate

    @Test(arguments: [
        ("scene.movie_night", "/api/services/scene/turn_on"),
        ("script.good_morning", "/api/services/script/turn_on"),
    ])
    func activatePostsTurnOnWithJSONBody(entityID: String, path: String) async throws {
        let fake = FakeHTTPClient(routes: [path: .json("[]")])
        try await client(fake).activate(entityID: entityID)
        let specs = await fake.receivedSpecs
        #expect(specs.count == 1)
        let spec = try #require(specs.first)
        #expect(spec.method == .post)
        #expect(spec.url.absoluteString == "https://ha.example.invalid\(path)")
        #expect(spec.headers["Authorization"] == "Bearer \(Fixtures.haToken)")
        #expect(spec.headers["Content-Type"] == "application/json")
        let body = try #require(spec.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["entity_id": entityID])
    }

    @Test(arguments: [
        "light.living_room", "switch.heater", "sensor.living_room_temperature", "automation.wake_up",
        "Scene.movie_night", "scene.Movie", "scene", "scene.", ".movie", "", "scene.movie.night",
        "scene/../../api.x", "scene.movie night", "script.a\"b",
    ])
    func activateRefusesNonActivatableOrInvalidIDsWithoutRequest(entityID: String) async throws {
        let fake = FakeHTTPClient.json("[]")
        await #expect(throws: HomeAssistantActionError.notActivatable) {
            try await client(fake).activate(entityID: entityID)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func activateFailuresAreNeverRetried() async throws {
        let outcomes: [(FakeHTTPClient.Outcome, ServiceProviderError)] = [
            (.unauthorized, .unauthorized),
            (.forbidden, .forbidden),
            (.timeout, .unreachable),
            (.serverError, .unexpectedStatus(500)),
            (.json(#"{"message":"Service not found."}"#, status: 400), .unexpectedStatus(400)),
        ]
        for (outcome, expected) in outcomes {
            let fake = FakeHTTPClient(outcome)
            await #expect(throws: expected) { try await client(fake).activate(entityID: "script.good_morning") }
            #expect(await fake.receivedSpecs.count == 1)
        }
    }

    @Test func activateIgnoresTheResponseBody() async throws {
        // POST answers the changed states; an empty or non-JSON 200 is still a success.
        try await client(FakeHTTPClient(.emptyBody)).activate(entityID: "scene.movie_night")
        try await client(FakeHTTPClient(.invalidJSON)).activate(entityID: "scene.movie_night")
    }

    // MARK: isValidEntityID

    @Test(arguments: [
        "sensor.living_room_temperature", "scene.movie_night", "script.good_morning",
        "sensor.a", "binary_sensor.door_2", "a.b",
    ])
    func isValidEntityIDAcceptsLowercaseDomainDotObjectID(id: String) {
        #expect(HomeAssistantClient.isValidEntityID(id))
    }

    @Test(arguments: [
        "", ".", "sensor", "sensor.", ".temperature", "sensor..temperature", "sensor.living.room",
        "Sensor.temperature", "sensor.Temperature", "SENSOR.TEMP",
        "../sensor.x", "sensor.../x", "sensor/../x.y", "sensor.x/y", "sensor.x?y=1", "sensor.x#y",
        "sensor.living room", "sensor.living-room", "sensor.température", " sensor.x", "sensor.x\n",
    ])
    func isValidEntityIDRejectsMalformedIDs(id: String) {
        #expect(!HomeAssistantClient.isValidEntityID(id))
    }

    @Test func isValidEntityIDBoundsLength() {
        let max = "sensor." + String(repeating: "a", count: 255 - 7)
        #expect(HomeAssistantClient.isValidEntityID(max))
        #expect(!HomeAssistantClient.isValidEntityID(max + "a"))
    }
}

@Suite("HAEntity")
struct HAEntityTests {
    @Test func domainIsThePrefixBeforeTheDot() {
        #expect(HAEntity(id: "sensor.power", state: "1").domain == "sensor")
        #expect(HAEntity(id: "binary_sensor.door", state: "on").domain == "binary_sensor")
        #expect(HAEntity(id: "nodot", state: "on").domain == "nodot")
    }

    @Test func onlyScenesAndScriptsAreActivatable() {
        #expect(HAEntity(id: "scene.movie_night", state: "x").isActivatable)
        #expect(HAEntity(id: "script.good_morning", state: "off").isActivatable)
        #expect(!HAEntity(id: "light.living_room", state: "on").isActivatable)
        #expect(!HAEntity(id: "automation.scene", state: "on").isActivatable)
        #expect(!HAEntity(id: "scenery.x", state: "on").isActivatable)
    }

    @Test func displayStateAppendsTheUnit() {
        #expect(HAEntity(id: "sensor.t", state: "21.5", unit: "°C").displayState == "21.5 °C")
        #expect(HAEntity(id: "sensor.h", state: "48", unit: "%").displayState == "48 %")
        #expect(HAEntity(id: "light.l", state: "on").displayState == "on")
    }

    @Test func unavailableAndUnknownStates() {
        #expect(HAEntity(id: "sensor.a", state: "unavailable").isUnavailable)
        #expect(HAEntity(id: "sensor.a", state: "unknown").isUnavailable)
        #expect(!HAEntity(id: "sensor.a", state: "0").isUnavailable)
    }

    @Test func memberwiseNameDefaultsToID() {
        #expect(HAEntity(id: "sensor.a", state: "1").name == "sensor.a")
        #expect(HAEntity(id: "sensor.a", name: "A", state: "1").name == "A")
    }

    @Test func decodingDefaultsMissingStateToUnknown() throws {
        let entity = try JSONDecoder().decode(HAEntity.self, from: Data(#"{"entity_id":"sensor.x"}"#.utf8))
        #expect(entity.state == "unknown")
        #expect(entity.name == "sensor.x")
        #expect(entity.isUnavailable)
    }
}
