import SwiftUI

struct OverviewView: View {
    var body: some View {
        ContentUnavailableView("Overview", systemImage: "internaldrive", description: Text("Coming soon."))
            .navigationTitle("Overview")
    }
}
