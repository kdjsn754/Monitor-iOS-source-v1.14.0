import SwiftUI

struct ModuleSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editMode: EditMode = .active

    var body: some View {
        List {
            Section {
                ForEach(model.moduleOrder) { module in
                    HStack {
                        Label(module.title, systemImage: module.icon)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.isVisible(module) },
                            set: { model.setModule(module, visible: $0) }
                        ))
                        .labelsHidden()
                    }
                }
                .onMove { source, destination in
                    model.moveModules(from: source, to: destination)
                }
            } footer: {
                Text("拖动右侧手柄调整顺序，开关控制显示。调整后返回概览立即生效。")
            }
        }
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden)
        .listRowBackground(Color(.secondarySystemGroupedBackground))
        .background(Color.clear)
        .navigationTitle("概览模块")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("恢复默认") {
                    model.resetModules()
                }
                .font(.caption)
            }
        }
    }
}
