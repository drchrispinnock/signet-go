import SwiftUI

/// "Confirm on your Ledger…" while a Ledger key signs (upstream's, from ConnectLedgerSheet).
struct LedgerPromptLabel: View {
    var text = "Confirm on your Ledger…"

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Label(text, systemImage: "lock.rectangle.stack").font(.callout).foregroundStyle(.secondary)
        }
    }
}
