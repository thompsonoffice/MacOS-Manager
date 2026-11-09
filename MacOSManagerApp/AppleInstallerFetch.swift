import Foundation
import MacOSManagerCore

enum AppleHTTPS {
    static func get(
        _ url: URL,
        maximumBytes: Int,
        allows: @escaping (URL) -> Bool,
        isCancelled: @escaping () -> Bool
    ) async throws -> Data {
        if isCancelled() { throw WorkflowError.cancelled }
        guard allows(url) else {
            throw SpokenInstallError(
                plainLanguage: "That address is not an Apple software catalog address. Nothing was downloaded.",
                rawDetail: url.absoluteString,
                allowsSoftwareUpdateFallback: false,
                allowsDirectPackageFallback: false
            )
        }
        let fetch = DataFetch(maximumBytes: maximumBytes, allows: allows, isCancelled: isCancelled)
        let session = URLSession(configuration: configuration(resourceTimeout: 180), delegate: fetch, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            return try await fetch.start(url, session: session)
        } catch {
            throw wrap(error)
        }
    }

    static func download(
        _ url: URL,
        to destination: URL,
        expectedSize: Int64,
        isCancelled: @escaping () -> Bool,
        onProgress: @escaping (String) -> Void
    ) async throws {
        guard AppleDownloadHosts.isInstallAssistantPackageURL(url) else {
            throw SpokenInstallError(
                plainLanguage: "The installer address is not on Apple's download server. Nothing was downloaded.",
                rawDetail: url.absoluteString,
                allowsSoftwareUpdateFallback: false,
                allowsDirectPackageFallback: false
            )
        }
        let box = DownloadBox(destination: destination, expected: expectedSize, isCancelled: isCancelled, onProgress: onProgress)
        let session = URLSession(configuration: configuration(resourceTimeout: 60 * 60 * 8), delegate: box, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            try await box.start(url, session: session)
        } catch {
            throw wrap(error)
        }
    }

    static func gunzipIfNeeded(_ data: Data) throws -> Data {
        guard data.count >= 2, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else {
            return data
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacOSManager-gzip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("catalog.gz")
        let output = directory.appendingPathComponent("catalog")
        try data.write(to: input)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", input.path]
        process.standardOutput = handle
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            try? handle.close()
            throw transport("The catalog was compressed and could not be opened.", detail: error.localizedDescription)
        }
        process.waitUntilExit()
        try handle.close()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw transport("The catalog was compressed and could not be opened.", detail: detail)
        }
        return try Data(contentsOf: output)
    }

    private static func configuration(resourceTimeout: TimeInterval) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = true
        return config
    }

    private static func transport(_ plain: String, detail: String) -> SpokenInstallError {
        SpokenInstallError(
            plainLanguage: plain,
            rawDetail: detail,
            allowsSoftwareUpdateFallback: true,
            allowsDirectPackageFallback: false
        )
    }

    private static func wrap(_ error: Error) -> Error {
        if error is WorkflowError || error is SpokenInstallError { return error }
        return SpokenInstallError(
            plainLanguage: "The download from Apple did not finish.",
            rawDetail: error.localizedDescription,
            allowsSoftwareUpdateFallback: true,
            allowsDirectPackageFallback: false
        )
    }
}

private final class DataFetch: NSObject, URLSessionDataDelegate {
    let maximumBytes: Int
    let allows: (URL) -> Bool
    let isCancelled: () -> Bool
    private var data = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var failure: Error?

    init(maximumBytes: Int, allows: @escaping (URL) -> Bool, isCancelled: @escaping () -> Bool) {
        self.maximumBytes = maximumBytes
        self.allows = allows
        self.isCancelled = isCancelled
    }

    func start(_ url: URL, session: URLSession) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.dataTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if isCancelled() {
            dataTask.cancel()
            return
        }
        if self.data.count + data.count > maximumBytes {
            failure = SpokenInstallError(
                plainLanguage: "Apple's response was larger than this step allows.",
                rawDetail: "\(self.data.count + data.count) bytes",
                allowsSoftwareUpdateFallback: true,
                allowsDirectPackageFallback: false
            )
            dataTask.cancel()
            return
        }
        self.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Data, Error>
        if let failure {
            result = .failure(failure)
        } else if isCancelled() {
            result = .failure(WorkflowError.cancelled)
        } else if let error {
            result = .failure(error)
        } else if let http = task.response as? HTTPURLResponse, http.statusCode != 200 {
            result = .failure(SpokenInstallError(
                plainLanguage: "Apple's server responded with status \(http.statusCode).",
                rawDetail: task.originalRequest?.url?.host ?? "",
                allowsSoftwareUpdateFallback: true,
                allowsDirectPackageFallback: false
            ))
        } else if task.response == nil {
            result = .failure(SpokenInstallError(
                plainLanguage: "Apple's server did not send a web response.",
                rawDetail: "",
                allowsSoftwareUpdateFallback: true,
                allowsDirectPackageFallback: false
            ))
        } else {
            result = .success(data)
        }
        continuation?.resume(with: result)
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, allows(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private final class DownloadBox: NSObject, URLSessionDownloadDelegate {
    let destination: URL
    let expected: Int64
    let isCancelled: () -> Bool
    let onProgress: (String) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var lastPercent = -1
    private var moved = false
    private var moveError: Error?

    init(destination: URL, expected: Int64, isCancelled: @escaping () -> Bool, onProgress: @escaping (String) -> Void) {
        self.destination = destination
        self.expected = expected
        self.isCancelled = isCancelled
        self.onProgress = onProgress
    }

    func start(_ url: URL, session: URLSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if isCancelled() {
            downloadTask.cancel()
            return
        }
        let total = expected > 0 ? expected : max(totalBytesExpectedToWrite, 0)
        let percent = total > 0 ? Int((totalBytesWritten * 100) / total) : -1
        guard percent != lastPercent else { return }
        lastPercent = percent
        onProgress(DownloadProgressText.line(bytes: totalBytesWritten, expected: total))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            moved = true
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Void, Error>
        if let moveError {
            result = .failure(moveError)
        } else if isCancelled() {
            result = .failure(WorkflowError.cancelled)
        } else if let error {
            result = .failure(error)
        } else if let http = task.response as? HTTPURLResponse, http.statusCode != 200 {
            result = .failure(SpokenInstallError(
                plainLanguage: "Apple's server responded with status \(http.statusCode).",
                rawDetail: task.originalRequest?.url?.host ?? "",
                allowsSoftwareUpdateFallback: true,
                allowsDirectPackageFallback: false
            ))
        } else if !moved {
            result = .failure(SpokenInstallError(
                plainLanguage: "The installer download did not produce a package file.",
                rawDetail: "",
                allowsSoftwareUpdateFallback: true,
                allowsDirectPackageFallback: false
            ))
        } else {
            result = .success(())
        }
        continuation?.resume(with: result)
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, AppleDownloadHosts.isInstallAssistantPackageURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum AppleCatalogClient {
    static func loadInstallerPackages(
        isCancelled: @escaping () -> Bool,
        onProgress: @escaping (String) -> Void
    ) async throws -> [CatalogInstallerPackage] {
        if isCancelled() { throw WorkflowError.cancelled }
        var lastError: Error?
        var parsed: [CatalogInstallerPackage] = []
        for url in AppleCatalogList.mergedCatalogURLs {
            if isCancelled() { throw WorkflowError.cancelled }
            onProgress("Reading Apple's catalog.")
            do {
                let data = try await AppleHTTPS.get(
                    url,
                    maximumBytes: 40_000_000,
                    allows: AppleDownloadHosts.isCatalogURL(_:),
                    isCancelled: isCancelled
                )
                let plain = try AppleHTTPS.gunzipIfNeeded(data)
                let packages = try SUCatalogParser.parse(plain)
                if !packages.isEmpty {
                    parsed = packages
                    break
                }
            } catch is CancellationError {
                throw WorkflowError.cancelled
            } catch let error as WorkflowError where error == .cancelled {
                throw error
            } catch {
                lastError = error
            }
        }
        if parsed.isEmpty {
            throw lastError ?? SpokenInstallError(
                plainLanguage: "Apple's catalog did not list an installer package. Nothing was downloaded.",
                rawDetail: "",
                allowsSoftwareUpdateFallback: true,
                allowsDirectPackageFallback: false
            )
        }
        var enriched: [CatalogInstallerPackage] = []
        for (index, package) in parsed.enumerated() {
            if isCancelled() { throw WorkflowError.cancelled }
            onProgress("Reading installer \(index + 1) of \(parsed.count), product \(package.productKey).")
            enriched.append(await describe(package, isCancelled: isCancelled, onProgress: onProgress))
        }
        return enriched
    }

    private static func describe(
        _ package: CatalogInstallerPackage,
        isCancelled: @escaping () -> Bool,
        onProgress: @escaping (String) -> Void
    ) async -> CatalogInstallerPackage {
        guard let distribution = package.distributionURL else { return package }
        var copy = package
        do {
            let data = try await AppleHTTPS.get(
                distribution,
                maximumBytes: 2_000_000,
                allows: AppleDownloadHosts.isDistributionURL(_:),
                isCancelled: isCancelled
            )
            let text = String(decoding: try AppleHTTPS.gunzipIfNeeded(data), as: UTF8.self)
            if let metadata = DistributionDocumentParser.parse(text) {
                copy.version = metadata.version
                copy.build = metadata.build
                copy.title = metadata.title
            }
        } catch {
            onProgress("The description for product \(package.productKey) could not be read.")
        }
        return copy
    }
}
