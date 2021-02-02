import UIKit
import WebKit
import PassKit
import SwiftProtobuf

@objc
public protocol SDKViewDismissDelegate : NSObjectProtocol {
    func sdkViewDismiss()
}

@objcMembers
public class SDKViewController: UIViewController, WKScriptMessageHandler, PaymentHandlerDelegate {
    
    public var token: String = ""
    public var baseUrl = "https://widget.setpartnerstv.com"
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
                    window.PNWidget = {};
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
        webView.allowsBackForwardNavigationGestures = true
        
        view.addSubview(webView)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        let url = URL(string: "\(baseUrl)/?token=\(token)")
        let request = URLRequest(url: url!)
        
        webView.load(request)
    }
    
    override public func viewSafeAreaInsetsDidChange() {
        webView.frame = view.safeAreaLayoutGuide.layoutFrame
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
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
                delegate.sdkViewDismiss()
            }
        }
    }
    
    private func isReadyToPayRequest() {
        var event = Pb_MobileEvent()
        event.type = Pb_MobileEventType.mobileEventApplepayIsReadyToPayResponse
        event.isReadyToPay = paymentHandler.canMakePayments()
        
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
}
