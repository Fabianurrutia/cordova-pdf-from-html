#import <Cordova/CDV.h>
#import <PDFKit/PDFKit.h>  // Use PDFKit for PDF generation
#import <WebKit/WebKit.h>  // Use WKWebView to render HTML

@interface PDFGenerator : CDVPlugin <UIDocumentInteractionControllerDelegate, WKNavigationDelegate>

@property (nonatomic, strong) WKWebView *webViewModified;  // Declare the WKWebView property
@property UIDocumentInteractionController *docController;
@property (readwrite, assign) BOOL hasPendingOperation;

- (void)htmlToPDF:(CDVInvokedUrlCommand*)command;

@end
