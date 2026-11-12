import SwiftUI
import WebKit

final class TileModel: ObservableObject {
    @Published var pageURL: URL?
    @Published var claudeRunning = false
    @Published var speaking = false
    @Published var error: String?
    weak var webView: WKWebView?
    var onPageLoaded: (() -> Void)?
    var onSync: (([String: Any]) -> Void)?
    var onNeedToken: (() -> Void)?

    func eval(_ js: String) { webView?.evaluateJavaScript(js, completionHandler: nil) }
}

/// WKWebView that lets a mouse-down on the page drag the borderless window.
final class DragWebView: WKWebView {
    override var mouseDownCanMoveWindow: Bool { true }
}

struct WebView: NSViewRepresentable {
    let url: URL
    let model: TileModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> DragWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []   // let the (silent) AudioContext start without a click
        // The page posts "ready" once window.claudeAvatar exists (after the avatar has loaded).
        for name in ["ready", "sync", "needToken"] { config.userContentController.add(context.coordinator, name: name) }
        let view = DragWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.isInspectable = true
        view.navigationDelegate = context.coordinator
        model.webView = view
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: DragWebView, context: Context) {
        if view.url != url { view.load(URLRequest(url: url)) }
    }

    /// Auto-recovery: reload if the web process dies or the page fails to load.
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: TileModel
        init(model: TileModel) { self.model = model }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "sync": if let body = message.body as? [String: Any] { model.onSync?(body) }
            case "needToken": model.onNeedToken?()
            default: model.onPageLoaded?()
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { webView.reload() }
        }
    }
}

/// Status dot. The speaking pulse is a Core Animation loop, so it costs no SwiftUI re-rendering.
struct StatusDot: NSViewRepresentable {
    let running: Bool
    let speaking: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        view.wantsLayer = true
        view.layer?.cornerRadius = 4
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let layer = view.layer else { return }
        layer.backgroundColor = (running ? NSColor.systemGreen : NSColor.systemGray).cgColor
        if speaking, layer.animation(forKey: "pulse") == nil {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1; scale.toValue = 1.6
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1; fade.toValue = 0.5
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 0.6
            group.autoreverses = true
            group.repeatCount = .infinity
            layer.add(group, forKey: "pulse")
        } else if !speaking {
            layer.removeAnimation(forKey: "pulse")
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: 8, height: 8)
    }
}

/// Round window button in the style of the macOS traffic lights.
struct WindowButton: View {
    let color: Color
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.65))
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: 13, height: 13)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct PillButton<Label: View>: View {
    let active: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.6))
                .frame(width: 20, height: 20)
                .background(active ? Color.white.opacity(0.22) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct TileView: View {
    @ObservedObject var model: TileModel
    @ObservedObject var app: AppState
    @State private var hovering = false
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.114, green: 0.114, blue: 0.122)
            if let url = model.pageURL {
                WebView(url: url, model: model).opacity(app.faceHidden ? 0 : 1)
            }
            if app.faceHidden {
                // Opaque cover so clicks don't reach the (paused) page.
                ZStack {
                    Color(red: 0.114, green: 0.114, blue: 0.122)
                    Circle().fill(.white.opacity(0.08)).frame(width: 64, height: 64)
                        .overlay(Text("C").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white.opacity(0.7)))
                }
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red).padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if hovering || showSettings { controls }
            HStack(spacing: 6) {
                StatusDot(running: model.claudeRunning, speaking: model.speaking)
                Text("Claude").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(10)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .ignoresSafeArea()
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    private var controls: some View {
        ZStack {
            HStack(spacing: 7) {
                WindowButton(color: .red, symbol: "xmark", help: "Hide (⌥⌘A or the menu-bar icon brings it back)") { app.toggleWindow() }
                WindowButton(color: .green, symbol: "arrow.up.left.and.arrow.down.right", help: "Maximize / restore") { app.toggleMaximize() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 2) {
                PillButton(active: app.pinned, help: app.pinned ? "Unpin from top" : "Keep on top", action: { app.pinned.toggle() }) {
                    Image(systemName: app.pinned ? "pin.fill" : "pin")
                }
                ForEach(Array(AppState.sizes.enumerated()), id: \.offset) { i, size in
                    PillButton(active: app.sizeIndex == i, help: "\(size.name) size", action: { app.setSize(i) }) { Text(size.name) }
                }
                PillButton(active: app.faceHidden, help: app.faceHidden ? "Show face" : "Hide face", action: { app.faceHidden.toggle() }) {
                    Image(systemName: app.faceHidden ? "eye.slash.fill" : "eye.slash")
                }
                // Same panel as the menu-bar icon (which macOS can hide on notched Macs when the bar is full).
                PillButton(active: showSettings, help: "Settings", action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }
                .popover(isPresented: $showSettings, arrowEdge: .bottom) { MenuPanel(app: app) }
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding(10)
        .transition(.opacity)
    }
}

struct MenuPanel: View {
    @ObservedObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { app.toggleWindow() } label: {
                HStack { Text(app.isVisible ? "Hide Avatar" : "Show Avatar"); Spacer(); Text("⌥⌘A").foregroundStyle(.secondary) }
            }

            Divider()

            Picker("Face", selection: $app.renderer) {
                Text("3D face (free)").tag(RendererKind.talkingHead)
                Text("Photoreal – Simli (your key)").tag(RendererKind.simli)
            }
            if app.renderer == .simli { SimliSettings(app: app) }

            if app.renderer == .talkingHead {
                Picker("Avatar", selection: $app.avatarID) {
                    ForEach(app.avatars) { Text($0.title).tag($0.id) }
                }
                Button("Open Custom Avatars Folder…") { app.openUserAvatarsFolder() }
                    .buttonStyle(.link).font(.caption)
            }

            if app.renderer == .talkingHead { VStack(alignment: .leading, spacing: 2) {
                HStack { Text("Mouth sensitivity"); Spacer(); Text(String(format: "%.1f×", app.sensitivity)).foregroundStyle(.secondary).monospacedDigit() }
                Slider(value: $app.sensitivity, in: 0.5...2.0)
            } }

            Toggle("Always on top", isOn: $app.pinned)
            Toggle("Launch at login", isOn: Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
            if let note = app.loginNote { Text(note).font(.caption).foregroundStyle(.secondary) }

            Divider()

            Button("Quit Claude Avatar") { app.quit() }.keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 270)
    }
}

struct SimliSettings: View {
    @ObservedObject var app: AppState
    @State private var keyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Simli is a cloud service with its own pricing and free tier. Claude's voice is sent to Simli to animate the face.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if app.hasSimliKey {
                HStack {
                    Label("API key saved in Keychain", systemImage: "key.fill").font(.caption)
                    Spacer()
                    Button("Remove") { app.removeSimliKey() }.buttonStyle(.link).font(.caption)
                }
            } else {
                HStack {
                    SecureField("Simli API key", text: $keyDraft).textFieldStyle(.roundedBorder)
                    Button("Save") { app.saveSimliKey(keyDraft); keyDraft = "" }.disabled(keyDraft.isEmpty)
                }
            }
            TextField("Face ID", text: $app.simliFaceID).textFieldStyle(.roundedBorder).font(.caption)
            if app.hasSimliKey {
                HStack {
                    Button("Test connection") { app.testSimliConnection() }.font(.caption)
                    if let status = app.keyStatus {
                        Text(status).font(.caption).foregroundStyle(app.keyStatusOK ? Color.green : Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack { Text("Sync nudge"); Spacer(); Text(String(format: "%+d ms", Int(app.syncOffsetMs))).foregroundStyle(.secondary).monospacedDigit() }
                Slider(value: $app.syncOffsetMs, in: -200...300, step: 10)
                Text(app.syncStatus).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let err = app.rendererError { Text(err).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
