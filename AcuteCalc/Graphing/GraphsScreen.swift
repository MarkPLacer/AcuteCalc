import SwiftUI

/// Which graph workspace is shown in the Graphs tab.
enum GraphSpace: String, CaseIterable, Identifiable {
    case plane, space, complex
    var id: String { rawValue }

    var title: String {
        switch self {
        case .plane: "2D"
        case .space: "3D"
        case .complex: "ℂ"
        }
    }

    var accessibilityName: String {
        switch self {
        case .plane: "Graf v ravnini"
        case .space: "Prostorski graf"
        case .complex: "Kompleksna ravnina"
        }
    }
}

/// The Graphs tab: 2D functions and relations, 3D surfaces, the complex plane.
struct GraphsScreen: View {
    @AppStorage("graphSpace") private var space: GraphSpace = .plane

    var body: some View {
        NavigationStack {
            Group {
                switch space {
                case .plane: GraphWorkspaceView()
                case .space: SurfaceWorkspaceView()
                case .complex: ComplexWorkspaceView()
                }
            }
            .navigationTitle("Grafi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Vrsta grafa", selection: $space) {
                        ForEach(GraphSpace.allCases) { space in
                            Text(space.title)
                                .accessibilityLabel(space.accessibilityName)
                                .tag(space)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            .sectionMenuToolbar()
        }
    }
}
