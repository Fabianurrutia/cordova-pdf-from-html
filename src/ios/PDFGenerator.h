#import <Cordova/CDV.h>
#import <PDFKit/PDFKit.h>
#import <WebKit/WebKit.h>

@interface PDFGenerator : CDVPlugin <UIDocumentInteractionControllerDelegate, WKNavigationDelegate>

@property (nonatomic, strong) WKWebView *webViewModified;
@property UIDocumentInteractionController *docController;
@property (readwrite, assign) BOOL hasPendingOperation;

- (void)htmlToPDF:(CDVInvokedUrlCommand*)command;

@end
