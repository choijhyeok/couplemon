import CryptoKit
import Foundation

struct GitHubRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let downloadURL: URL
        let size: Int
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case size
            case digest
        }
    }

    let tagName: String
    let pageURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
        case assets
    }

    var version: String? {
        let value = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        return UpdateService.versionComponents(value) == nil ? nil : value
    }
    var installer: Asset? { assets.first { $0.name == "CoupleMon.pkg" } }
}

struct UpdateService {
    enum UpdateError: LocalizedError {
        case invalidResponse
        case noRelease
        case missingInstaller
        case invalidDownloadURL
        case invalidDownload
        case missingChecksum
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "GitHub 업데이트 응답을 확인할 수 없습니다."
            case .noRelease: "아직 배포된 업데이트가 없습니다."
            case .missingInstaller: "최신 Release에 CoupleMon.pkg가 없습니다."
            case .invalidDownloadURL: "업데이트 다운로드 주소가 올바르지 않습니다."
            case .invalidDownload: "업데이트 파일 다운로드에 실패했습니다."
            case .missingChecksum: "업데이트 파일의 SHA-256 정보가 없습니다."
            case .checksumMismatch: "업데이트 파일 검증에 실패했습니다."
            }
        }
    }

    static let currentVersion = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "0.0.0"

    private let latestReleaseURL = URL(
        string: "https://api.github.com/repos/choijhyeok/couplemon/releases/latest"
    )!

    func latestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CoupleMon-Updater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        if response.statusCode == 404 { throw UpdateError.noRelease }
        guard (200..<300).contains(response.statusCode) else { throw UpdateError.invalidResponse }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    func downloadInstaller(from release: GitHubRelease) async throws -> URL {
        guard let asset = release.installer else { throw UpdateError.missingInstaller }
        guard let version = release.version else { throw UpdateError.invalidResponse }
        guard
            asset.downloadURL.scheme == "https",
            asset.downloadURL.host == "github.com",
            asset.downloadURL.path.hasPrefix("/choijhyeok/couplemon/releases/download/")
        else { throw UpdateError.invalidDownloadURL }

        let (temporaryURL, response) = try await URLSession.shared.download(from: asset.downloadURL)
        guard
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            response.url?.scheme == "https",
            (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) == asset.size
        else { throw UpdateError.invalidDownload }

        guard let digest = asset.digest, digest.hasPrefix("sha256:") else {
            throw UpdateError.missingChecksum
        }
        let data = try Data(contentsOf: temporaryURL)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == digest.dropFirst("sha256:".count) else {
            throw UpdateError.checksumMismatch
        }

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoupleMon", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("CoupleMon-\(version).pkg")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard
            let candidate = versionComponents(candidate),
            let current = versionComponents(current)
        else { return false }
        return candidate.lexicographicallyPrecedes(current) == false && candidate != current
    }

    fileprivate static func versionComponents(_ version: String) -> [Int]? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard
            components.count == 3,
            components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else { return nil }
        let values = components.compactMap { Int($0) }
        return values.count == 3 ? values : nil
    }
}
