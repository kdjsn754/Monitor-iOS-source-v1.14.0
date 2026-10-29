import SwiftUI

/// 二级页：三档秒数 + 每个数据项挂哪一档，原来挤在设置页的两块内容搬到这里。
struct PollSettingsView: View {
    @EnvironmentObject private var model: AppModel

    private var enabledCount: Int {
        PollItem.allCases.filter { model.pollConfig.tier(for: $0) != nil }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                presetCard
                tierCard
                itemCard
            }
            .padding(16)
        }
        .background(Color.clear)
        .navigationTitle("采集与刷新")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") {
                    model.resetPollConfig()
                }
                .font(.caption)
            }
        }
    }

    // MARK: - 预设

    private var presetCard: some View {
        SectionCard("一键预设", icon: "wand.and.stars") {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(PollPreset.allCases) { preset in
                        Button {
                            model.applyPreset(preset)
                        } label: {
                            VStack(spacing: 3) {
                                Text(preset.title)
                                    .font(.subheadline.weight(.medium))
                                Text("\(Int(preset.fast)) / \(Int(preset.medium)) / \(Int(preset.slow))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color(.tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("数字是快 / 中 / 慢三档的秒数。预设只改秒数，不动每个数据项挂在哪一档。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 三档秒数

    private var tierCard: some View {
        SectionCard("更新频率", icon: "timer") {
            VStack(spacing: 14) {
                ForEach(Array(PollTier.allCases.enumerated()), id: \.element.id) { index, tier in
                    if index > 0 {
                        Divider().opacity(0.4)
                    }
                    tierRow(tier)
                }

                Text("同一档里的数据项会合并成一条命令发给路由器，进程数不变，只是频率不同。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func tierRow(_ tier: PollTier) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(tier.title)
                    .font(.subheadline.weight(.medium))
                Text("\(model.items(in: tier).count) 项")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                secondsStepper(tier)
            }
            Text(tier.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func secondsStepper(_ tier: PollTier) -> some View {
        let value = model.seconds(for: tier)
        let range = tier.secondsRange
        return HStack(spacing: 9) {
            Button {
                model.setSeconds(value - tier.step, for: tier)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(value > range.lowerBound ? Color.blue : Color(.tertiaryLabel))
            .disabled(value <= range.lowerBound)

            Text("\(Int(value)) 秒")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 52)

            Button {
                model.setSeconds(value + tier.step, for: tier)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(value < range.upperBound ? Color.blue : Color(.tertiaryLabel))
            .disabled(value >= range.upperBound)
        }
    }

    // MARK: - 数据项

    private var itemCard: some View {
        SectionCard("数据项", icon: "list.bullet.below.rectangle") {
            VStack(spacing: 12) {
                ForEach(Array(PollItem.allCases.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().opacity(0.35)
                    }
                    itemRow(item)
                }

                Divider().opacity(0.5)

                Text(model.pollConfig.disabledCount > 0
                     ? "已开启 \(enabledCount) 项，关闭的 \(model.pollConfig.disabledCount) 项对应的卡片会停在最后一次的值。"
                     : "共 \(enabledCount) 项，全部开启。关掉某项后对应卡片不再刷新。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func itemRow(_ item: PollItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if item.isRequired {
                Text("固定快档")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            } else {
                tierMenu(item)
            }
        }
    }

    private func tierMenu(_ item: PollItem) -> some View {
        let current = model.pollConfig.tier(for: item)
        return Menu {
            ForEach(PollTier.allCases) { tier in
                Button {
                    model.setTier(tier, for: item)
                } label: {
                    Label("\(tier.title)（\(Int(model.seconds(for: tier))) 秒）",
                          systemImage: current == tier ? "checkmark.circle.fill" : "circle")
                }
            }
            Divider()
            Button {
                model.setTier(nil, for: item)
            } label: {
                Label("关闭（不采集）", systemImage: "slash.circle")
            }
        } label: {
            HStack(spacing: 4) {
                Text(current?.title ?? "关闭")
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                current == nil ? Color(.tertiarySystemFill) : Color.blue.opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(current == nil ? Color.secondary : Color.blue)
        }
    }
}
