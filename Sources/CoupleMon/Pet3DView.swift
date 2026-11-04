import SwiftUI
import WebKit

final class Pet3DSchemeHandler: NSObject, WKURLSchemeHandler {
    let modelURL: URL
    var partnerURL: URL?
    init(modelURL: URL) { self.modelURL = modelURL }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard let url = urlSchemeTask.request.url, url.host == "character" else { throw URLError(.badURL) }
            let files: [String: (String, String)] = [
                "/viewer.html": ("viewer.html", "text/html"), "/viewer.js": ("viewer.js", "text/javascript"),
                "/motion-player.js": ("motion-player.js", "text/javascript"),
                "/couple-scene.js": ("couple-scene.js", "text/javascript"),
                "/pet-props.js": ("pet-props.js", "text/javascript"),
                "/reward-items.js": ("reward-items.js", "text/javascript"),
                "/vendor/three.module.min.js": ("vendor/three.module.min.js", "text/javascript"),
                "/vendor/three.core.min.js": ("vendor/three.core.min.js", "text/javascript"),
                "/vendor/GLTFLoader.js": ("vendor/GLTFLoader.js", "text/javascript"),
                "/vendor/BufferGeometryUtils.js": ("vendor/BufferGeometryUtils.js", "text/javascript"),
            ]
            let file: URL
            let mime: String
            if url.path == "/model.glb" { file = modelURL; mime = "model/gltf-binary" }
            else if url.path == "/partner.glb", let partnerURL { file = partnerURL; mime = "model/gltf-binary" }
            else if let entry = files[url.path], let resources = Bundle.module.resourceURL {
                file = resources.appendingPathComponent("Pet3D").appendingPathComponent(entry.0)
                mime = entry.1
            } else { throw URLError(.fileDoesNotExist) }
            let data = try Data(contentsOf: file)
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) { }
}

struct Pet3DView: NSViewRepresentable {
    let modelURL: URL
    var activityID: UUID? = nil
    var action: Pet3DAction = .idle
    var event: String? = nil
    var level: Int = 1
    var rewardLevel: Int? = nil
    var randomEnabled = false
    var randomInterval = 5
    var partnerURL: URL? = nil
    var performance: CouplePetPerformance? = nil
    var onTap: (() -> Void)? = nil
    var onStatus: ((Bool) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let scheme = Pet3DSchemeHandler(modelURL: modelURL)
        scheme.partnerURL = partnerURL
        context.coordinator.scheme = scheme
        configuration.setURLSchemeHandler(scheme, forURLScheme: "couplemon-pet")
        configuration.userContentController.add(context.coordinator, name: "pet3d")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        context.coordinator.onTap = onTap
        context.coordinator.onStatus = onStatus
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.action = action
        context.coordinator.event = event
        context.coordinator.level = level
        context.coordinator.rewardLevel = rewardLevel
        context.coordinator.randomEnabled = randomEnabled
        context.coordinator.randomInterval = randomInterval
        context.coordinator.activityID = activityID
        context.coordinator.partnerURL = partnerURL
        context.coordinator.performance = performance
        view.load(URLRequest(url: URL(string: "couplemon-pet://character/viewer.html")!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        coordinator.onStatus = onStatus
        coordinator.reduceMotion = reduceMotion
        coordinator.level = level
        coordinator.rewardLevel = rewardLevel
        coordinator.randomEnabled = randomEnabled
        coordinator.randomInterval = randomInterval
        coordinator.action = action
        coordinator.event = event
        coordinator.partnerURL = partnerURL
        coordinator.scheme?.partnerURL = partnerURL
        coordinator.performance = performance
        if coordinator.ready {
            coordinator.syncAppearance(in: view)
        }
        if coordinator.activityID != activityID {
            coordinator.activityID = activityID
            if coordinator.ready { coordinator.play(in: view) }
        }
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "pet3d")
        view.loadHTMLString("", baseURL: nil)
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var activityID: UUID?
        var reduceMotion = false
        var ready = false
        var action = Pet3DAction.idle
        var event: String?
        var level = 1
        var rewardLevel: Int?
        var randomEnabled = false
        var randomInterval = 5
        var scheme: Pet3DSchemeHandler?
        var partnerURL: URL?
        var performance: CouplePetPerformance?
        var onTap: (() -> Void)?
        var onStatus: ((Bool) -> Void)?
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "tap" { onTap?() }
            if type == "ready" {
                ready = true
                if let view = message.webView {
                    syncAppearance(in: view)
                    if activityID != nil || !randomEnabled { play(in: view) }
                }
                onStatus?(true)
            }
            if type == "error" { onStatus?(false) }
        }
        func syncAppearance(in view: WKWebView) {
            let reward = rewardLevel.flatMap { $0 <= level ? PetLevelReward.reward(at: $0) : nil }
            view.evaluateJavaScript("window.pet3D?.setReducedMotion(\(reduceMotion ? "true" : "false")); window.pet3D?.setLevel(\(min(100, max(1, level)))); window.pet3D?.setReward(\(reward?.javascript ?? "null")); window.pet3D?.setRandomMode(\(randomEnabled ? "true" : "false"), \(min(30, max(3, randomInterval))))", completionHandler: nil)
            let partner = partnerURL.map { "./partner.glb?v=" + $0.deletingPathExtension().lastPathComponent }
            let encodedPartner = (try? JSONEncoder().encode(partner)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
            let encodedPerformance = (try? JSONEncoder().encode(performance)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
            view.evaluateJavaScript("window.pet3D?.setPartner(\(encodedPartner)); window.pet3D?.performTogether(\(encodedPerformance))", completionHandler: nil)
        }
        func play(in view: WKWebView) {
            let allowedEvent = ["chat", "sendingLetter", "receivingLetter"].contains(event ?? "") ? event! : ""
            view.evaluateJavaScript("window.pet3D?.playAction('\(action.rawValue)', '\(allowedEvent)')", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            decisionHandler(url?.scheme == "couplemon-pet" && url?.host == "character" ? .allow : .cancel)
        }
    }
}
