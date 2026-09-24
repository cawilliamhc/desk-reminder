import DeskCore
import SwiftUI

/// Time has opened up. Here's what could go in it.
///
/// The banner never does anything by itself. Two or three options, one of
/// them always "leave it open", and the day changes only when Apply is
/// pressed - and then only until Undo.
struct RebalanceBanner: View {
    let rebalance: Rebalance
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(rebalance.title)
                    .font(Theme.ui(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 12)
                Text("Just now").font(Theme.ui(11)).foregroundStyle(Theme.muted)
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(rebalance.options) { option in
                    optionCard(option)
                }
            }

            HStack(spacing: 10) {
                Button("Apply") { model.applyRebalance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Not now") { model.dismissRebalance() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Text("Nothing you've placed moves unless you pick it.")
                    .font(Theme.ui(11)).foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.background)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func optionCard(_ option: Rebalance.Option) -> some View {
        let selected = model.rebalanceChoice == option.id
        return Button {
            model.rebalanceChoice = option.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(option.label).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink)
                Text(option.detail)
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Theme.primary : Theme.border, lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// What was done with the freed time, and the way back.
struct RebalanceStrip: View {
    let strip: AppModel.RebalanceStrip
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Text(strip.text).font(Theme.ui(12)).foregroundStyle(Theme.ink)
            Spacer(minLength: 12)
            Button("Undo") { model.undoRebalance() }
                .buttonStyle(.borderless)
                .font(Theme.ui(12))
                .foregroundStyle(Theme.primary)
            Button {
                model.hideRebalanceStrip()
            } label: {
                Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
