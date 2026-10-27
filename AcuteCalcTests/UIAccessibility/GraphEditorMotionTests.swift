import SwiftUI
import Testing
@testable import AcuteCalc

/// UI-09 (Graphs tab): with Reduce Motion the function editor eases in and out instead of
/// springing open (and cross-fades instead of sliding up, editorTransition, which as an
/// AnyTransition cannot be compared); with the setting off it keeps the snappy spring. Before
/// the fix the workspace did not read Reduce Motion and always used .snappy(duration: 0.3).
@MainActor
@Suite struct GraphEditorMotionTests {
    @Test func reduceMotionEasesInsteadOfSpringing() {
        #expect(GraphWorkspaceView.editorAnimation(reduceMotion: true) == Animation.easeInOut(duration: 0.2))
        #expect(GraphWorkspaceView.editorAnimation(reduceMotion: true) != Animation.snappy(duration: 0.3))
    }

    @Test func defaultKeepsTheSnappySpring() {
        #expect(GraphWorkspaceView.editorAnimation(reduceMotion: false) == Animation.snappy(duration: 0.3))
    }
}
