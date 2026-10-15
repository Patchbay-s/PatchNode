import WidgetKit
import SwiftUI

@main
struct PatchNodeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GlobalStatusWidget()
        ProxmoxNodesWidget()
        ContainerIssuesWidget()
    }
}
