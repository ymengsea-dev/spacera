import SwiftUI

struct CleanupView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showsHistory = false

    var body: some View {
        @Bindable var model = env.cleanup
        Group {
            if model.hasResult {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            if model.isLimitedScan { LimitedScanBanner() }
                            ForEach(model.sections, id: \.category) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(section.category.title).font(.title3.weight(.semibold))
                                    ForEach(section.findings) { finding in
                                        CategoryCard(finding: finding, model: model)
                                    }
                                }
                            }
                            if model.sections.isEmpty {
                                ContentUnavailableView("All Clean", systemImage: "checkmark.seal", description: Text("Nothing to clean up was found."))
                            }
                        }
                        .padding(24)
                    }
                    Divider()
                    HStack {
                        Button("History…") { showsHistory = true }
                        Spacer()
                        Text("Selected: \(model.selectedSize.formattedBytes)")
                            .font(.headline).monospacedDigit()
                        Button("Review…") { model.startReview() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(model.selectedItems.isEmpty)
                    }
                    .padding(14)
                }
                .onAppear { model.syncSelection() }
                .onChange(of: env.store.result?.date) { model.syncSelection() }
            } else {
                ContentUnavailableView("No Scan Yet", systemImage: "sparkles",
                                       description: Text("Scan your disk to find caches, developer junk, and leftovers you can safely remove."))
            }
        }
        .navigationTitle("Cleanup")
        .sheet(item: $model.review) { ReviewSheet(model: $0) }
        .sheet(isPresented: $showsHistory) { HistorySheet(model: model) }
    }
}

private struct HistorySheet: View {
    var model: CleanupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cleanup History").font(.title2.weight(.semibold)).padding(20)
            List {
                ForEach(model.history) { batch in
                    Section("\(batch.date.formatted(date: .abbreviated, time: .shortened)) · \(batch.trashedSize.formattedBytes)") {
                        ForEach(batch.outcomes) { outcome in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(outcome.item.name).lineLimit(1)
                                    Text(outcome.item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                switch outcome.status {
                                case .trashed:
                                    Button("Put Back") { Task { await model.putBack(outcome) } }
                                case .restored:
                                    Text("Put back").foregroundStyle(.secondary)
                                default:
                                    Text(outcome.message ?? outcome.status.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if model.history.isEmpty { ContentUnavailableView("No Cleanups Yet", systemImage: "clock") }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 560, height: 480)
        .task { await model.loadHistory() }
    }
}
