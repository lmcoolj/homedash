//
//  ContentView.swift
//  server-dashboard
//

import SwiftUI
import WebKit
import Combine

private let dashboardURL = URL(string: "http://192.168.68.98:3030")!

struct ContentView: View {
    @StateObject private var model = WebViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            WebViewContainer(model: model)
                .ignoresSafeArea(.container, edges: .bottom)

            if model.isLoading {
                ProgressView()
                    .padding(.top, 8)
            }

            if let error = model.lastError {
                VStack(spacing: 12) {
                    Text("Can't reach the server")
                        .font(.headline)
                    Text(error)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Try again") { model.reload() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
        }
    }
}

final class WebViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: String?
    weak var webView: WKWebView?

    func reload() {
        lastError = nil
        if let webView, webView.url != nil {
            webView.reload()
        } else {
            webView?.load(URLRequest(url: dashboardURL))
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let model: WebViewModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.refreshControl = context.coordinator.makeRefreshControl(for: webView)
        model.webView = webView
        webView.load(URLRequest(url: dashboardURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: WebViewModel
        init(model: WebViewModel) { self.model = model }

        func makeRefreshControl(for webView: WKWebView) -> UIRefreshControl {
            let rc = UIRefreshControl()
            rc.addAction(UIAction { [weak webView] _ in
                webView?.reload()
            }, for: .valueChanged)
            return rc
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
            model.lastError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.isLoading = false
            webView.scrollView.refreshControl?.endRefreshing()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(with: error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(with: error, webView: webView)
        }

        private func finish(with error: Error, webView: WKWebView) {
            model.isLoading = false
            model.lastError = error.localizedDescription
            webView.scrollView.refreshControl?.endRefreshing()
        }
    }
}

#Preview {
    ContentView()
}
