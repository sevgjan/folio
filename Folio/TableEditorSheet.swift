import SwiftUI

struct TableCandidate: Identifiable {
    let id = UUID()
    let range: NSRange
    let table: MarkdownTableFormatter.ParsedTable
}

struct TableEditorSheet: View {
    let candidates: [TableCandidate]
    let onSave: ([TableCandidate]) -> Void
    let onCancel: () -> Void

    @State private var editedTables: [MarkdownTableFormatter.ParsedTable]
    @State private var selectedIndex = 0

    init(candidates: [TableCandidate], onSave: @escaping ([TableCandidate]) -> Void, onCancel: @escaping () -> Void) {
        self.candidates = candidates
        self.onSave = onSave
        self.onCancel = onCancel
        _editedTables = State(initialValue: candidates.map(\.table))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edit Table")
                    .font(.headline)

                if candidates.count > 1 {
                    Picker("Table", selection: $selectedIndex) {
                        ForEach(candidates.indices, id: \.self) { index in
                            Text("Table \(index + 1)").tag(index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }

                Spacer()

                Button {
                    addColumn()
                } label: {
                    Label("Add Column", systemImage: "rectangle.split.3x1")
                }
                Button {
                    addRow()
                } label: {
                    Label("Add Row", systemImage: "rectangle.split.1x2")
                }
            }
            .padding()

            Divider()

            if editedTables.indices.contains(selectedIndex) {
                ScrollView([.horizontal, .vertical]) {
                    TableGrid(table: $editedTables[selectedIndex])
                        .padding()
                }
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done") {
                    let results = zip(candidates, editedTables).map { candidate, table in
                        TableCandidate(range: candidate.range, table: table)
                    }
                    onSave(results)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 720, idealWidth: 940, minHeight: 460, idealHeight: 560)
    }

    private func addRow() {
        guard editedTables.indices.contains(selectedIndex) else { return }
        let columnCount = editedTables[selectedIndex].alignments.count
        editedTables[selectedIndex].rows.append([String](repeating: "", count: columnCount))
    }

    private func addColumn() {
        guard editedTables.indices.contains(selectedIndex) else { return }
        editedTables[selectedIndex].alignments.append(.left)
        for rowIndex in editedTables[selectedIndex].rows.indices {
            editedTables[selectedIndex].rows[rowIndex].append("")
        }
    }
}

private struct TableGrid: View {
    @Binding var table: MarkdownTableFormatter.ParsedTable

    private var columnCount: Int { table.alignments.count }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(table.rows.indices, id: \.self) { rowIndex in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { columnIndex in
                        TextField("", text: $table.rows[rowIndex][columnIndex])
                            .textFieldStyle(.roundedBorder)
                            .font(rowIndex == 0 ? .body.bold() : .body)
                            .frame(minWidth: 120)
                    }
                    Button(role: .destructive) {
                        removeRow(rowIndex)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(table.rows.count <= 1)
                }
            }
            GridRow {
                ForEach(0..<columnCount, id: \.self) { columnIndex in
                    Button(role: .destructive) {
                        removeColumn(columnIndex)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(columnCount <= 1)
                }
            }
        }
    }

    private func removeRow(_ index: Int) {
        guard table.rows.count > 1, table.rows.indices.contains(index) else { return }
        table.rows.remove(at: index)
    }

    private func removeColumn(_ index: Int) {
        guard columnCount > 1, table.alignments.indices.contains(index) else { return }
        table.alignments.remove(at: index)
        for rowIndex in table.rows.indices where table.rows[rowIndex].indices.contains(index) {
            table.rows[rowIndex].remove(at: index)
        }
    }
}
