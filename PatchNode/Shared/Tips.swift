import SwiftUI
import TipKit

/// Discreet tips (TipKit) to discover what isn't obvious: the dashboard order,
/// the tabs, widgets, notifications, iCloud, PromQL charts and Home Assistant
/// entities. At most one a day, never during the demo, each gone for good once
/// closed or once the user did what it suggests.
nonisolated enum PatchNodeTips {
    /// Once, at launch.
    static func configure() {
        try? Tips.configure([.displayFrequency(.daily), .datastoreLocation(.applicationDefault)])
    }

    /// The demo is for exploring with sample data: no tip on top of it.
    @Parameter static var demoMode: Bool = false
}

nonisolated struct DashboardOrderTip: Tip {
    /// Cards shown on the dashboard: reordering is worth it from three.
    @Parameter static var cardCount: Int = 0

    var title: Text { Text("Your cards, your order") }
    var message: Text? { Text("Tap the arrows to put the cards you check most at the top.") }
    var image: Image? { Image(systemName: "arrow.up.arrow.down") }
    var rules: [Rule] {
        [#Rule(PatchNodeTips.$demoMode) { $0 == false }, #Rule(Self.$cardCount) { $0 >= 3 }]
    }
}

nonisolated struct WidgetTip: Tip {
    /// The dashboard seen with data, on different days.
    static let dashboardSeen = Event(id: "dashboardSeen")

    var title: Text { Text("Your HomeLab on the Home Screen") }
    var message: Text? { Text("Touch and hold the Home Screen, tap Edit, then Add Widget, and search for PatchNode.") }
    var image: Image? { Image(systemName: "square.grid.2x2") }
    var rules: [Rule] {
        [#Rule(PatchNodeTips.$demoMode) { $0 == false }, #Rule(Self.dashboardSeen) { $0.donations.donatedWithin(.week).count >= 3 }]
    }
}

nonisolated struct TabsTip: Tip {
    var title: Text { Text("Choose your tabs") }
    var message: Text? { Text("Put up to 4 screens in the tab bar; the others open from their dashboard card.") }
    var image: Image? { Image(systemName: "dock.rectangle") }
    var rules: [Rule] { [#Rule(PatchNodeTips.$demoMode) { $0 == false }] }
}

nonisolated struct NotificationsTip: Tip {
    var title: Text { Text("Be told when something breaks") }
    var message: Text? { Text("Turn on local notifications for the problems you care about. They are off by default.") }
    var image: Image? { Image(systemName: "bell.badge") }
    var rules: [Rule] { [#Rule(PatchNodeTips.$demoMode) { $0 == false }] }
}

nonisolated struct ICloudTip: Tip {
    var title: Text { Text("The same setup on your other devices") }
    var message: Text? { Text("Sync your configuration through your own iCloud, or export it as a file or a QR code.") }
    var image: Image? { Image(systemName: "icloud") }
    var rules: [Rule] { [#Rule(PatchNodeTips.$demoMode) { $0 == false }] }
}

nonisolated struct PromQLChartTip: Tip {
    var title: Text { Text("Chart any PromQL query") }
    var message: Text? { Text("Save a query, CPU or disk usage for example, to see it here every time.") }
    var image: Image? { Image(systemName: "chart.xyaxis.line") }
    var rules: [Rule] { [#Rule(PatchNodeTips.$demoMode) { $0 == false }] }
}

nonisolated struct HomeEntitiesTip: Tip {
    var title: Text { Text("Pick what matters") }
    var message: Text? { Text("Choose the sensors, lights, scenes and scripts to show here and on the dashboard.") }
    var image: Image? { Image(systemName: "checklist") }
    var rules: [Rule] { [#Rule(PatchNodeTips.$demoMode) { $0 == false }] }
}
