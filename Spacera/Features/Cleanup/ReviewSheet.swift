import SwiftUI

struct ReviewSheet: View {
    @Bindable var model: ReviewViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            switch model.stage {
            case .review: reviewContent
            case .working:
                ProgressView("Moving to Trash…").padding(60)
            case .done(let batch): DoneView(batch: batch, dismiss: { dismiss() })
            }
        }
        .frame(width: 620, height: 560)
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review Before Moving to Trash").font(.title2.weight(.semibold))
                Text("\(model.plan.entries.count) items · \(model.plan.totalSize.formattedBytes). Everything goes to the Trash, so you can put it back until you empty the Trash.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            List {
                if !model.plan.runningOwners.isEmpty {
                    Section {
                        ForEach(model.plan.runningOwners.sorted(), id: \.self) { id in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                Text("\(model.appName(for: id)) is open. Quit it first so it doesn't recreate or depend on these files.")
                                Spacer()
                                Button("Quit \(model.appName(for: id))") { Task { await model.quit(bundleID: id) } }
                            }
                        }
                    }
                }
                ForEach(model.groupedEntries, id: \.0) { level, entries in
                    Section {
                        ForEach(entries) { entry in EntryRow(entry: entry) }
                    } header: {
                        HStack {
                            SafetyBadge(level: level)
                            Spacer()
                            SizeLabel(bytes: entries.reduce(0) { $0 + $1.item.size }, font: .caption)
                        }
                    }
                }
                if !model.plan.rejected.isEmpty {
                    Section("Won't be touched") {
                        ForEach(model.plan.rejected, id: \.item.path) { rejected in
                            VStack(alignment: .leading) {
                                Text(rejected.item.name)
                                Text(rejected.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            VStack(alignment: .leading, spacing: 12) {
                if model.plan.requiresUserDataConfirmation {
                    Toggle(isOn: $model.confirmedUserData) {
                        Text("I understand some of these items contain my own data.")
                    }
                    .toggleStyle(.checkbox)
                }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Move \(model.plan.totalSize.formattedBytes) to Trash") {
                        Task { await model.moveToTrash() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canConfirm)
                }
            }
            .padding(20)
        }
    }
}

private struct EntryRow: View {
    var entry: CleanupPlan.Entry

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.name).lineLimit(1)
                Text(entry.item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                ForEach(Array(entry.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(text(for: warning), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            SizeLabel(bytes: entry.item.size, font: .callout)
        }
    }

    private func text(for warning: CleanupPlan.Warning) -> String {
        switch warning {
        case .ownerRunning: "Its app is open"
        case .changedSinceScan: "Changed since the scan; size may differ"
        case .missing: "No longer exists; it will be skipped"
        }
    }
}

private struct DoneView: View {
    var batch: TrashBatch
    var dismiss: () -> Void

    var failures: [TrashOutcome] { batch.outcomes.filter { $0.status == .failed || $0.status == .blocked } }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green)
            Text("Moved \(batch.trashedSize.formattedBytes) to the Trash").font(.title2.weight(.semibold))
            Text("Empty the Trash to free the space. Changed your mind? Use Put Back in Cleanup › History.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if !failures.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(failures.count) items couldn't be moved").font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(failures) { outcome in
                                VStack(alignment: .leading) {
                                    Text(outcome.item.name)
                                    Text(outcome.message ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                .card()
            }
            Spacer()
            HStack {
                Button("Open Trash") { Finder.openTrash() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
    }
}
