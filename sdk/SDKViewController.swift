import UIKit
import WebKit
import PassKit
import SwiftProtobuf

@objc
public protocol SDKViewDismissDelegate : NSObjectProtocol {
    func sdkViewDismiss(error: Error?)
}

@objcMembers
public class SDKViewController: UIViewController, WKScriptMessageHandler, PaymentHandlerDelegate, WKNavigationDelegate, WKUIDelegate {
    
    public var token: String = ""
    public var baseUrl = "https://widget.ogon.ru"
    public var queryItems: [URLQueryItem] = []
    public var httpUsername = ""
    public var httpPassword = ""
    public var applePayEnabled = false
    public weak var dismissDelegate: SDKViewDismissDelegate?
    
    private var webView: WKWebView!
    private var paymentHandler: PaymentHandler!
    
    override public func loadView() {
        super.loadView()
        
        paymentHandler = PaymentHandler()
        paymentHandler.paymentDelegate = self
        
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let userScript = WKUserScript(
            source: """
                (function(){
                    window.PNWidget = window.PNWidget || {};
                    window.PNWidget._listeners = new Set();
                        
                    window.PNWidget.sendMobileEvent = function sendMobileEvent(event) {
                        window.webkit.messageHandlers.PNWidget.postMessage(JSON.stringify(event));
                    };
                    
                    window.PNWidget.onMobileEvent = function onMobileEvent(listener) {
                        window.PNWidget._listeners.add(listener);
                    
                        return function unsubscribe() {
                            window.PNWidget._listeners.delete(listener);
                        };
                    };

                    function wrap(fn) {
                        return function wrapper() {
                            var res = fn.apply(this, arguments);
                            window.webkit.messageHandlers.navigationStateChange.postMessage(null);
                            return res;
                        }
                    }

                    history.pushState = wrap(history.pushState);
                    history.replaceState = wrap(history.replaceState);
                    window.addEventListener('popstate', function() {
                        window.webkit.messageHandlers.navigationStateChange.postMessage(null);
                    });

                    if (window.PNWidget.onready) {
                        window.PNWidget.onready();
                    }
                })()
            """,
            injectionTime: WKUserScriptInjectionTime.atDocumentStart,
            forMainFrameOnly: true
        )
        
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.preferences = preferences
        webConfiguration.userContentController.add(self, name: "PNWidget")
        webConfiguration.userContentController.add(self, name: "navigationStateChange")
        webConfiguration.userContentController.addUserScript(userScript)
        webConfiguration.websiteDataStore =  WKWebsiteDataStore.default()
        
        webView = WKWebView(frame: view.bounds, configuration: webConfiguration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        view.addSubview(webView)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        var urlComponents = URLComponents(string: baseUrl)!
        urlComponents.queryItems = queryItems
        
        if !token.isEmpty {
            urlComponents.queryItems?.append(URLQueryItem(name: "token", value: token))
        }
        
        let request = URLRequest(url: urlComponents.url!)
        
        webView.load(request)
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
    
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if (navigationAction.targetFrame == nil || !navigationAction.targetFrame!.isMainFrame) {
            webView.load(navigationAction.request)
        }

        return nil
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    @available(iOS 13.0, *)
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        let pref = WKWebpagePreferences()
        if #available(iOS 14.0, *) {
            pref.allowsContentJavaScript = true
        }
        pref.preferredContentMode = .recommended

        decisionHandler(.allow, pref)
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {

        if let response = navigationResponse.response as? HTTPURLResponse {
            if response.statusCode >= 400 && navigationResponse.isForMainFrame {
                //webView.allowsBackForwardNavigationGestures = false
                self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
                handleNavigationError(error: NSError(domain: "sdk:webview", code: 1, userInfo: nil))
            }
        }
        
        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error: error)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error: error)
    }
    
    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard !httpUsername.isEmpty && !httpPassword.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard challenge.proposedCredential?.user != httpUsername || challenge.proposedCredential?.password != httpPassword else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let credential = URLCredential(user: httpUsername, password: httpPassword, persistence: .none)
        completionHandler(.useCredential, credential)
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        debugPrint(message.name)
        debugPrint(message.body)
        
        if (message.name == "navigationStateChange") {
            navigationStateChange();
            return;
        }
        
        var options = JSONDecodingOptions()
        options.ignoreUnknownFields = true
        
        if let event = try?	Pb_MobileEvent(jsonString: message.body as! String, options: options) {
            handleEvent(event: event)
        }
    }
    
    func didAuthorizePayment(payment: PKPayment) {
        var data = Pb_ApplePayPaymentData()
        data.token = Pb_ApplePayPaymentToken()
        data.token.paymentMethod = Pb_ApplePaymentMethod()
        data.token.paymentData = payment.token.paymentData.base64EncodedString()
        data.token.transactionIdentifier = payment.token.transactionIdentifier
        data.token.paymentMethod.displayName = payment.token.paymentMethod.displayName ?? ""
        data.token.paymentMethod.network = payment.token.paymentMethod.network?.rawValue ?? ""
        data.token.paymentMethod.type = getPaymentMethodTypeName(type: payment.token.paymentMethod.type)
        
        var event = Pb_MobileEvent()
        event.type = Pb_MobileEventType.mobileEventApplepayPaymentDataResponse
        event.applepayPaymentData = data
        
        sendEvent(event: event)
    }
    
    private func sendEvent(event: Pb_MobileEvent) {
        var options = JSONEncodingOptions()
        options.preserveProtoFieldNames = true
        
        if let json = try? event.jsonString(options: options) {
            let js = """
                (function() {
                    const event = \(json);
                    for (let listener of window.PNWidget._listeners.values()) {
                        listener(event);
                    }
                })()
            """
            
            webView.evaluateJavaScript(js)
        }
        
    }
    
    private func handleEvent(event: Pb_MobileEvent) {
        switch event.type {
        case Pb_MobileEventType.mobileEventApplepayIsReadyToPayRequest:
            isReadyToPayRequest()
            break
        case Pb_MobileEventType.mobileEventApplepayPaymentDataRequest:
            paymentHandler.startPayment(request: event.applepayPaymentDataRequest)
            break
        case Pb_MobileEventType.mobileEventOpenURLRequest:
            openURL(url: event.openURLRequest)
            break
        case Pb_MobileEventType.mobileEventShareURLRequest:
            shareURL(url: event.shareURLRequest)
            break
            
        default: break
        }
    }
    
    private func navigationStateChange() {
        if (webView.url!.relativeString.hasSuffix("/escape")) {
//            dismiss(animated: true) {}
            if let delegate = self.dismissDelegate {
                delegate.sdkViewDismiss(error: nil)
            }
        }
    }
    
    private func isReadyToPayRequest() {
        var event = Pb_MobileEvent()
        event.type = Pb_MobileEventType.mobileEventApplepayIsReadyToPayResponse
        event.isReadyToPay = applePayEnabled && paymentHandler.canMakePayments()
        
        sendEvent(event: event)
    }
    
    private func openURL(url: String) {
        if let link = URL(string: url) {
            UIApplication.shared.open(link)
        }
    }
    
    private func shareURL(url: String) {
        if let link = URL(string: url) {
            let activityViewController = UIActivityViewController(activityItems: [link], applicationActivities: nil)
            activityViewController.excludedActivityTypes = [.airDrop, .mail]
            
            present(activityViewController, animated: true)
        }
    }
    
    private func handleNavigationError(error: Error) {
        if !webView.canGoBack {
            if let delegate = self.dismissDelegate {
                delegate.sdkViewDismiss(error: error)
            }
        }
    }
    
    private func getPaymentMethodTypeName(type: PKPaymentMethodType) -> String {
        switch type {
        case .unknown:
            return "unknown"
        case .debit:
            return "debit"
        case .credit:
            return "credit"
        case .prepaid:
            return "prepaid"
        case .store:
            return "store"
        default:
            return "unknown"
        }
    }
}
