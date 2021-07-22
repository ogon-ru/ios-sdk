import PassKit

protocol PaymentHandlerDelegate : NSObjectProtocol {
    func didAuthorizePayment(payment: PKPayment)
}

class PaymentHandler : NSObject, PKPaymentAuthorizationControllerDelegate {
    weak var paymentDelegate: PaymentHandlerDelegate?
    
    func canMakePayments() -> Bool {
        return PKPaymentAuthorizationController.canMakePayments()
    }
    
    func startPayment(request: Pb_ApplePayPaymentDataRequest) {
        let total = PKPaymentSummaryItem(label: request.total.label, amount: NSDecimalNumber(string: request.total.amount), type: .final)
        let paymentRequest = PKPaymentRequest()
        paymentRequest.paymentSummaryItems = [total]
        paymentRequest.merchantIdentifier = "merchant.ru.ogon"
        paymentRequest.merchantCapabilities = .capability3DS
        paymentRequest.countryCode = request.countryCode
        paymentRequest.currencyCode = request.currencyCode
        paymentRequest.supportedNetworks = [.masterCard, .visa]
        
        let paymentController = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        paymentController.delegate = self
        paymentController.present(completion: { (presented: Bool) in
            if presented {
                debugPrint("Presented payment controller")
            } else {
                debugPrint("Failed to present payment controller")
            }
        })
    }
    
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        
        // Perform some very basic validation on the provided contact information
        let errors = [Error]()
        let status = PKPaymentAuthorizationStatus.success
        
        // Here you would send the payment token to your server or payment provider to process
        // Once processed, return an appropriate status in the completion handler (success, failure, etc)
        paymentDelegate?.didAuthorizePayment(payment: payment)
        
        completion(PKPaymentAuthorizationResult(status: status, errors: errors))
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss {}
    }
}

