import Testing
@testable import PatchNodeCore

struct TabSelectionTests {
    let everything = AppScreen.allCases

    @Test func defaultIsDashboardAndFirstThreeConfiguredScreens() {
        let available = AppScreen.available(for: [.glances, .proxmoxVE, .tailscale, .dockerSocketProxy, .crowdSec])
        #expect(available == [.dashboard, .proxmox, .docker, .security, .tailscale, .glances])
        #expect(TabSelection.resolve(stored: nil, available: available) == [.dashboard, .proxmox, .docker, .security])
    }

    @Test func neverMoreThanFourTabs() {
        let stored: [AppScreen] = [.dashboard, .glances, .tailscale, .backups, .docker, .security]
        #expect(TabSelection.resolve(stored: stored, available: everything).count == TabSelection.maxTabs)
    }

    @Test func deletedServiceScreenDisappears() {
        let stored: [AppScreen] = [.dashboard, .proxmox, .homeAssistant]
        let available = AppScreen.available(for: [.proxmoxVE])
        #expect(TabSelection.resolve(stored: stored, available: available) == [.dashboard, .proxmox])
    }

    @Test func userOrderIsKept() {
        let stored: [AppScreen] = [.glances, .dashboard, .proxmox]
        #expect(TabSelection.resolve(stored: stored, available: everything) == [.glances, .dashboard, .proxmox])
    }

    @Test func dashboardAlwaysStays() {
        #expect(TabSelection.resolve(stored: [.proxmox], available: everything) == [.dashboard, .proxmox])
        #expect(!TabSelection.canToggle(.dashboard, in: [.dashboard]))
    }

    @Test func fifthScreenCannotBeSwitchedOn() {
        let tabs: [AppScreen] = [.dashboard, .proxmox, .docker, .security]
        #expect(!TabSelection.canToggle(.glances, in: tabs))
        #expect(TabSelection.toggled(.glances, in: tabs) == tabs)
        #expect(TabSelection.canToggle(.docker, in: tabs))
        #expect(TabSelection.toggled(.docker, in: tabs) == [.dashboard, .proxmox, .security])
        #expect(TabSelection.toggled(.glances, in: [.dashboard, .proxmox]) == [.dashboard, .proxmox, .glances])
    }

    @Test func encodingRoundTripsAndSkipsUnknownScreens() {
        let tabs: [AppScreen] = [.dashboard, .homeAssistant]
        #expect(TabSelection.decode(TabSelection.encode(tabs)) == tabs)
        #expect(TabSelection.decode("") == nil)
        #expect(TabSelection.decode("dashboard,retired,glances") == [.dashboard, .glances])
    }

    @Test func everyKindHasAScreen() {
        #expect(AppScreen.available(for: ServiceKind.allCases) == AppScreen.allCases)
    }
}
