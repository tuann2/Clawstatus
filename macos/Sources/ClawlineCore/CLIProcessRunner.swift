import Foundation

/// Runs short-lived CLI processes with a single, cancellation-safe lifecycle.
/// Raw stdout and stderr are never logged by this type.
public enum CLIProcessRunner {
    public final class Session: @unchecked Sendable {
        private let sendHandler: @Sendable (Data) -> Void
        private let closeInputHandler: @Sendable () -> Void
        private let finishHandler: @Sendable (Swift.Result<Data, Error>) -> Void

        fileprivate init(
            send: @escaping @Sendable (Data) -> Void,
            closeInput: @escaping @Sendable () -> Void,
            finish: @escaping @Sendable (Swift.Result<Data, Error>) -> Void
        ) {
            sendHandler = send
            closeInputHandler = closeInput
            finishHandler = finish
        }

        public func send(_ data: Data) { sendHandler(data) }
        public func closeStandardInput() { closeInputHandler() }
        public func succeed(with data: Data) { finishHandler(.success(data)) }
        public func fail(with error: Error) { finishHandler(.failure(error)) }
    }

    public struct Configuration: Sendable {
        public let executable: String
        public let arguments: [String]
        public let currentDirectoryURL: URL?
        public let standardInput: Data?
        public let environmentOverrides: [String: String]
        public let timeout: TimeInterval

        public init(
            executable: String,
            arguments: [String],
            currentDirectoryURL: URL? = nil,
            standardInput: Data? = nil,
            environmentOverrides: [String: String] = [:],
            timeout: TimeInterval
        ) {
            self.executable = executable
            self.arguments = arguments
            self.currentDirectoryURL = currentDirectoryURL
            self.standardInput = standardInput
            self.environmentOverrides = environmentOverrides
            self.timeout = timeout
        }
    }

    public struct Result: Sendable {
        public let stdout: Data
        public let terminationStatus: Int32
    }

    public enum RunnerError: LocalizedError, Equatable, Sendable {
        case timedOut
        case exited(Int32)

        public var errorDescription: String? {
            switch self {
            case .timedOut: "CLI process timed out"
            case .exited(let status): "CLI process exited with status \(status)"
            }
        }
    }

    public static func run(_ configuration: Configuration) async throws -> Result {
        try await run(configuration, streamHandler: nil)
    }

    public static func runStreaming(
        _ configuration: Configuration,
        onOutput: @escaping @Sendable (Data, Session) -> Void
    ) async throws -> Result {
        try await run(configuration, streamHandler: onOutput)
    }

    private static func run(
        _ configuration: Configuration,
        streamHandler: (@Sendable (Data, Session) -> Void)?
    ) async throws -> Result {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let state = ProcessState(
                        configuration: configuration,
                        streamHandler: streamHandler,
                        continuation: continuation
                    )
                    guard box.install(state) else { return }
                    state.start()
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    static func firstExecutable(in candidates: [String]) -> String? {
        candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state: ProcessState?
    private var cancelled = false

    func install(_ state: ProcessState) -> Bool {
        lock.lock()
        self.state = state
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { state.finish(.failure(CancellationError())) }
        return !shouldCancel
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let state = state
        lock.unlock()
        state?.finish(.failure(CancellationError()))
    }
}

private final class ProcessState: @unchecked Sendable {
    private let configuration: CLIProcessRunner.Configuration
    private let streamHandler: (@Sendable (Data, CLIProcessRunner.Session) -> Void)?
    private let continuation: CheckedContinuation<CLIProcessRunner.Result, Error>
    private let process = Process()
    private let output = Pipe()
    private let error = Pipe()
    private var input: Pipe?
    private var inputClosed = false
    private let lock = NSLock()
    private var completed = false
    private var stdout = Data()
    private var outputReachedEOF = false
    private var errorReachedEOF = false
    private var terminationStatus: Int32?
    private var timeoutWorkItem: DispatchWorkItem?

    init(
        configuration: CLIProcessRunner.Configuration,
        streamHandler: (@Sendable (Data, CLIProcessRunner.Session) -> Void)?,
        continuation: CheckedContinuation<CLIProcessRunner.Result, Error>
    ) {
        self.configuration = configuration
        self.streamHandler = streamHandler
        self.continuation = continuation
    }

    func start() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        process.executableURL = URL(fileURLWithPath: configuration.executable)
        process.arguments = configuration.arguments
        process.currentDirectoryURL = configuration.currentDirectoryURL
        if !configuration.environmentOverrides.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(
                configuration.environmentOverrides,
                uniquingKeysWith: { _, override in override }
            )
        }
        if configuration.standardInput != nil || streamHandler != nil {
            let input = Pipe()
            self.input = input
            process.standardInput = input
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { [weak self] process in
            self?.handleTermination(process.terminationStatus)
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleOutput(handle.availableData)
        }
        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleError(handle.availableData)
        }
        do {
            try process.run()
            lock.unlock()
            if let standardInput = configuration.standardInput {
                send(standardInput)
                if streamHandler == nil { closeInputIfActive() }
            }
            scheduleTimeout()
        } catch {
            lock.unlock()
            finish(.failure(error))
        }
    }

    private func scheduleTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(.failure(CLIProcessRunner.RunnerError.timedOut))
        }
        lock.lock()
        guard !completed else { lock.unlock(); return }
        timeoutWorkItem = workItem
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + configuration.timeout,
            execute: workItem
        )
    }

    private func handleOutput(_ data: Data) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        if data.isEmpty {
            outputReachedEOF = true
        } else {
            stdout.append(data)
        }
        let result = completionResultIfReady()
        lock.unlock()
        if data.isEmpty { output.fileHandleForReading.readabilityHandler = nil }
        if !data.isEmpty, let streamHandler {
            let session = CLIProcessRunner.Session(
                send: { [weak self] data in self?.send(data) },
                closeInput: { [weak self] in self?.closeInputIfActive() },
                finish: { [weak self] result in
                    switch result {
                    case .success(let data):
                        self?.finish(.success(.init(stdout: data, terminationStatus: 0)))
                    case .failure(let error):
                        self?.finish(.failure(error))
                    }
                }
            )
            streamHandler(data, session)
        }
        if let result { finish(result) }
    }

    private func send(_ data: Data) {
        lock.lock()
        guard !completed, !inputClosed, let input else { lock.unlock(); return }
        input.fileHandleForWriting.write(data)
        lock.unlock()
    }

    private func closeInputIfActive() {
        lock.lock()
        guard !completed, !inputClosed, let input else { lock.unlock(); return }
        inputClosed = true
        input.fileHandleForWriting.closeFile()
        lock.unlock()
    }

    private func handleError(_ data: Data) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        // Always drain and discard stderr. It may contain account details.
        if data.isEmpty { errorReachedEOF = true }
        let result = completionResultIfReady()
        lock.unlock()
        if data.isEmpty { error.fileHandleForReading.readabilityHandler = nil }
        if let result { finish(result) }
    }

    private func handleTermination(_ status: Int32) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        terminationStatus = status
        let result = completionResultIfReady()
        lock.unlock()
        if let result { finish(result) }
    }

    private func completionResultIfReady() -> Swift.Result<CLIProcessRunner.Result, Error>? {
        guard let terminationStatus, outputReachedEOF, errorReachedEOF else { return nil }
        guard terminationStatus == 0 else {
            return .failure(CLIProcessRunner.RunnerError.exited(terminationStatus))
        }
        return .success(.init(stdout: stdout, terminationStatus: terminationStatus))
    }

    func finish(_ result: Swift.Result<CLIProcessRunner.Result, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let inputHandle = inputClosed ? nil : input?.fileHandleForWriting
        inputClosed = true
        let timeoutWorkItem = timeoutWorkItem
        self.timeoutWorkItem = nil
        lock.unlock()

        timeoutWorkItem?.cancel()
        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        inputHandle?.closeFile()
        if process.isRunning { process.terminate() }
        continuation.resume(with: result)
    }
}
