import SwiftUI

struct TestSuiteView: View {
    @StateObject private var runner = TidalDriftTestRunner.shared
    
    private let categories = ["Permissions", "Bonjour", "Network", "Security", "TidalDrop", "LocalCast"]
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            Divider()
            
            if runner.results.isEmpty && !runner.isRunning {
                emptyState
            } else {
                resultsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Integration Test Suite")
                        .font(.headline)
                    
                    statusLabel
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    if runner.isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    
                    Button("Run All Tests") {
                        Task { await runner.runAll() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(runner.isRunning)
                    
                    if !runner.results.isEmpty {
                        Button("Clear") {
                            runner.results = []
                            runner.status = .idle
                        }
                        .buttonStyle(.bordered)
                        .disabled(runner.isRunning)
                    }
                }
            }
            
            if case .running(let current, let progress) = runner.status {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text(current)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var statusLabel: some View {
        switch runner.status {
        case .idle:
            Text("Ready to run")
                .font(.caption)
                .foregroundColor(.secondary)
        case .running:
            Text("Running...")
                .font(.caption)
                .foregroundColor(.orange)
        case .finished(let passed, let failed):
            HStack(spacing: 12) {
                Label("\(passed) passed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                if failed > 0 {
                    Label("\(failed) failed", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "testtube.2")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Run the test suite to verify all TidalDrift subsystems")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Tests cover: Bonjour discovery, TCP/UDP networking,\nencryption, file transfer, and screen capture")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(categories, id: \.self) { category in
                    let catResults = runner.results.filter { $0.category == category }
                    if !catResults.isEmpty {
                        Section {
                            ForEach(catResults) { result in
                                TestResultRow(result: result)
                            }
                        } header: {
                            CategoryHeader(
                                category: category,
                                results: catResults,
                                onRun: {
                                    Task { await runner.runCategory(category) }
                                },
                                isRunning: runner.isRunning
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }
}

struct CategoryHeader: View {
    let category: String
    let results: [TestResult]
    let onRun: () -> Void
    let isRunning: Bool
    
    private var passCount: Int { results.filter(\.passed).count }
    private var failCount: Int { results.filter { !$0.passed }.count }
    
    var body: some View {
        HStack {
            Text(category)
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 6) {
                if failCount > 0 {
                    Text("\(failCount) failed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                }
                Text("\(passCount)/\(results.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(failCount == 0 ? .green : .secondary)
                
                Button(action: onRun) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(isRunning)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct TestResultRow: View {
    let result: TestResult
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: result.statusIcon)
                    .font(.system(size: 14))
                    .foregroundColor(result.passed ? .green : .red)
                
                Text(result.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Spacer()
                
                Text(String(format: "%.1fs", result.duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            
            if isExpanded {
                Text(result.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(result.passed ? .secondary : .red)
                    .padding(.leading, 28)
                    .padding(.bottom, 6)
                    .padding(.trailing, 8)
                    .textSelection(.enabled)
            }
            
            Divider()
        }
    }
}

struct TestSuiteView_Previews: PreviewProvider {
    static var previews: some View {
        TestSuiteView()
            .frame(width: 600, height: 520)
    }
}
