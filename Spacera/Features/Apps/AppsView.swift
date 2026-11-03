import SwiftUI

struct AppsView: View {
    var body: some View {
        ContentUnavailableView("Apps", systemImage: "square.grid.2x2", description: Text("Coming soon."))
            .navigationTitle("Apps")
    }
}
