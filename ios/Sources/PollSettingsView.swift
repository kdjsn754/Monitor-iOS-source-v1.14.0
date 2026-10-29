import SwiftUI

/// 二级页：只剩一个刷新间隔可以调，下面是「哪一页采哪些数据」的清单。
struct PollSettingsView: View {
    @EnvironmentObject private var model: AppModel

    private var seconds: Double { model.pollSeconds }
    private let presets: [Double] = [1, 2, 3, 5, 10]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                secondsCard
                itemsCard
                noteCard
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
                    model.setPollSeconds(2)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - 刷新间隔

    private var secondsCard: some View {
        SectionCard("刷新间隔", icon: "timer") {
            VStack(spacing: 14) {
                HStack(spacing: 18) {
                    Button {
                        model.setPollSeconds(seconds - 1)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 27))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(seconds > PollConfiguration.range.lowerBound
                                     ? Color.blue : Color(.tertiaryLabel))
                    .disabled(seconds <= PollConfiguration.range.lowerBound)

                    VStack(spacing: 2) {
                        Text("\(Int(seconds))")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("秒")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        model.setPollSeconds(seconds + 1)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 27))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(seconds < PollConfiguration.range.upperBound
                                     ? Color.blue : Color(.tertiaryLabel))
                    .disabled(seconds >= PollConfiguration.range.upperBound)
                }

                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { value in
                        Button {
                            model.setPollSeconds(value)
                        } label: {
                            Text("\(Int(value)) 秒")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    abs(seconds - value) < 0.5
                                        ? Color.blue.opacity(0.14)
                                        : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                                .foregroundStyle(abs(seconds - value) < 0.5
                                                 ? Color.blue : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 数据项清单

    private var itemsCard: some View {
        SectionCard("采集内容", icon: "list.bullet.below.rectangle") {
            VStack(spacing: 14) {
                ForEach(AppPage.allCases) { page in
                    pageBlock(page)
                }
            }
        }
    }

    @ViewBuilder
    private func pageBlock(_ page: AppPage) -> some View {
        let items = model.pollConfig.items(on: page)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                header(page, count: items.count)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().opacity(0.35)
                        }
                        itemRow(item)
                    }
                }
            }
        }
    }

    private func header(_ page: AppPage, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: page.icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.blue)
            Text(page.title)
                .font(.caption.weight(.semibold))
            Text("\(count) 项")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if page == model.activePage {
                Text("进行中")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12), in: Capsule())
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(item.isPeriodic ? "每 \(Int(seconds)) 秒" : "进页面时")
                .font(.system(size: 10).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(item.isPeriodic ? Color.blue : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (item.isPeriodic ? Color.blue : Color(.systemGray)).opacity(0.12),
                    in: Capsule()
                )
        }
        .padding(.vertical, 8)
    }

    // MARK: - 说明

    private var noteCard: some View {
        SectionCard("省在哪儿", icon: "leaf") {
            VStack(alignment: .leading, spacing: 7) {
                bullet("只采当前页面：在概览页就只取 CPU、内存、网速、温度、闪存和设备，切到「设置」页完全停止采集。")
                bullet("同一页的数据拼成一条命令、一个 shell 跑完，所以 2 秒一轮也只创建一次进程。")
                bullet("OpenClash 的模式和配置文件列表要问 7 次 uci，只在进入代理页时取一次；之后每轮只确认运行状态、端口和流量。")
                bullet("所有脚本都以 nice -n 19 执行，永远不抢转发和代理解析的 CPU。")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(Color.blue.opacity(0.5))
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
