/// Work off the main actor, like `await Task.detached(priority:) { … }.value`, that is also cancelled
/// when the task awaiting it is cancelled (a newer keystroke, viewport or interval; `.task(id:)`
/// restarting). A detached task does not inherit cancellation, so stale work used to run to its end
/// although its result was then thrown away. The work stops early only where it checks
/// `Task.isCancelled`; the caller still discards the result of a cancelled task.
nonisolated enum BackgroundWork {
    static func run<T: Sendable>(priority: TaskPriority, _ work: @escaping @Sendable () -> T) async -> T {
        let job = Task.detached(priority: priority) { work() }
        return await withTaskCancellationHandler {
            await job.value
        } onCancel: {
            job.cancel()
        }
    }
}
