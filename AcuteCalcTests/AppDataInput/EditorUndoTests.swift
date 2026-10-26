import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// Records the targets whose undo actions were removed. Whether removeAllActions(withTarget:) also drops
/// the emptied undo group is not documented, so canUndo cannot show it.
final class EditorUndoRecordingManager: UndoManager {
    private(set) var removedTargets: [ObjectIdentifier] = []

    override func removeAllActions(withTarget target: Any) {
        removedTargets.append(ObjectIdentifier(target as AnyObject))
        super.removeAllActions(withTarget: target)
    }
}

@MainActor
@Suite struct EditorUndoTests {
    /// PLT-02: the editor models are @State of the 2D, 3D and ℂ workspaces, which GraphsScreen swaps. The
    /// undo manager keeps only an unowned reference to the target, so a step of a released model crashed
    /// the next undo. Before the fix nothing removes the step. (This test never calls undo(): before the
    /// fix that would message a released object.)
    @Test func releasedEditorRemovesItsUndoSteps() async throws {
        let manager = EditorUndoRecordingManager()
        manager.groupsByEvent = false
        weak var released: FunctionEditorModel?
        var identifier: ObjectIdentifier?
        do {
            let model = FunctionEditorModel()
            model.undoManager = manager
            manager.beginUndoGrouping()
            model.press(.digit(3))   // registers an undo step with target `model`
            manager.endUndoGrouping()
            #expect(manager.canUndo)
            identifier = ObjectIdentifier(model)
            released = model
        }
        let id = try #require(identifier)
        let removed = try await AppDataInputTestSupport.wait(timeout: .seconds(2)) { manager.removedTargets.contains(id) }
        #expect(released == nil)   // as after switching the Graphs space from 2D to 3D
        #expect(removed)
    }

    /// PLT-04: load(_:) starts a new editing session (another function); an undo there wrote the old
    /// text of the previous function into the new one.
    @Test func undoDoesNotReachIntoThePreviousSession() {
        let manager = UndoManager()
        manager.groupsByEvent = false
        let model = FunctionEditorModel()
        model.undoManager = manager

        model.load(MathRow.text("12"))   // session 1: f₁
        manager.beginUndoGrouping()
        model.press(.digit(3))           // f₁ = 123
        manager.endUndoGrouping()

        model.load(MathRow.text("45"))   // session 2: f₂, changes are written to f₂
        var writtenToF2: [MathRow] = []
        model.onChange = { writtenToF2.append($0) }
        if manager.canUndo { manager.undo() }

        #expect(writtenToF2.isEmpty)     // before the fix: [12], the old text of f₁ lands in f₂
        #expect(model.editor.root == MathRow.text("45"))
    }
}
