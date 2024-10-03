#import "PDFGenerator.h"
#import <objc/runtime.h>  // Import the Objective-C runtime
#import <PDFKit/PDFKit.h>  // Import PDFKit

@implementation PDFGenerator

@synthesize hasPendingOperation;

- (void)htmlToPDF:(CDVInvokedUrlCommand*)command {
    self.hasPendingOperation = YES;

    NSString *urlString = [command argumentAtIndex:0 withDefault:NULL];
    NSString *htmlString = [command argumentAtIndex:1 withDefault:NULL];
    NSString *fileName = [command argumentAtIndex:5 withDefault:@"file.pdf"];
    NSString *outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];

    NSLog(@"[HTMLToPDF] Starting conversion with URL: %@ or HTML String: %@", urlString, htmlString);

    // Initialize a fully hidden WKWebView (not part of view hierarchy)
    if (!self.webViewModified) {
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        self.webViewModified = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config]; // Zero frame, no visible interaction
        self.webViewModified.navigationDelegate = self;  // Set the delegate
        self.webViewModified.hidden = YES;  // Ensure hidden
        [self.webViewModified setOpaque:NO];  // Ensure it does not have a visible background

        NSLog(@"[HTMLToPDF] WebView created and configured.");
    }

    if (urlString) {
        NSURL *url = [NSURL URLWithString:urlString];
        NSLog(@"[HTMLToPDF] Loading URL: %@", urlString);
        [self convertHTMLFromURL:url outputFile:outputPath command:command];
    } else if (htmlString) {
        NSLog(@"[HTMLToPDF] Loading HTML string...");
        [self convertHTML:htmlString outputFile:outputPath command:command];
    }
}

// Convert HTML from a URL using WKWebView
- (void)convertHTMLFromURL:(NSURL*)url outputFile:(NSString*)outputPath command:(CDVInvokedUrlCommand*)command {
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    NSLog(@"[convertHTMLFromURL] Sending request for URL: %@", url);
    [self.webViewModified loadRequest:request];  // Load the URL request

    // Associate outputPath and command with WKWebView
    objc_setAssociatedObject(self.webViewModified, "outputPathKey", outputPath, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self.webViewModified, "commandKey", command, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Convert an HTML string using WKWebView
- (void)convertHTML:(NSString*)htmlString outputFile:(NSString*)outputPath command:(CDVInvokedUrlCommand*)command {
    NSLog(@"[convertHTML] Loading HTML string...");
    [self.webViewModified loadHTMLString:htmlString baseURL:nil];  // Load the HTML string

    // Associate outputPath and command with WKWebView
    objc_setAssociatedObject(self.webViewModified, "outputPathKey", outputPath, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self.webViewModified, "commandKey", command, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - WKWebView Delegate

// WKWebView Delegate when navigation finishes
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"[WebView] Navigation finished.");
    NSString *outputPath = objc_getAssociatedObject(webView, "outputPathKey");
    CDVInvokedUrlCommand *command = objc_getAssociatedObject(webView, "commandKey");

    // Inject JavaScript to ensure background images are rendered
    NSString *enableBackgroundImagesJS = @"document.body.style.webkitPrintColorAdjust = 'exact';";

    [webView evaluateJavaScript:enableBackgroundImagesJS completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[WebView] Error injecting JS to enable background images: %@", error.localizedDescription);
        }

        // Once the JS is injected, proceed to create the PDF
        [self createPDFUsingPrintFormatterFromWebView:webView outputFile:outputPath command:command];
    }];
}

// WKWebView Delegate when navigation fails (optional, but useful)
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"[WebView] Navigation failed with error: %@", error);
}

// WKWebView Delegate when content fails to load (optional)
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"[WebView] Content load failed with error: %@", error);
}

// Generate PDF using UIPrintPageRenderer
- (void)createPDFUsingPrintFormatterFromWebView:(WKWebView *)webView outputFile:(NSString *)outputPath command:(CDVInvokedUrlCommand *)command {
    // Initialize UIPrintPageRenderer
    UIPrintPageRenderer *renderer = [[UIPrintPageRenderer alloc] init];

    // Add the WebView's print formatter to the renderer
    [renderer addPrintFormatter:[webView viewPrintFormatter] startingAtPageAtIndex:0];

    // Paper size: A4
    CGRect paperRect = CGRectMake(0, 0, 595.0, 842.0); // A4 dimensions in points
    CGRect printableRect = CGRectInset(paperRect, 20, 20); // Define margins

    // Set the paper and printable area
    [renderer setValue:[NSValue valueWithCGRect:paperRect] forKey:@"paperRect"];
    [renderer setValue:[NSValue valueWithCGRect:printableRect] forKey:@"printableRect"];

    // Create PDF context
    NSMutableData *pdfData = [NSMutableData data];
    UIGraphicsBeginPDFContextToData(pdfData, CGRectZero, nil);

    for (NSInteger i = 0; i < [renderer numberOfPages]; i++) {
        UIGraphicsBeginPDFPage();
        CGRect bounds = UIGraphicsGetPDFContextBounds();
        [renderer drawPageAtIndex:i inRect:bounds];
    }

    // End PDF context
    UIGraphicsEndPDFContext();

    // Write PDF data to file
    BOOL success = [pdfData writeToFile:outputPath atomically:YES];
    if (success) {
        NSLog(@"[createPDFUsingPrintFormatter] PDF successfully written to file.");
    } else {
        NSLog(@"[createPDFUsingPrintFormatter] Error writing PDF to file.");
    }

    // Send back the result
    NSString *option = [command argumentAtIndex:4 withDefault:@"base64"];
    if ([option isEqualToString:@"base64"]) {
        NSString *base64PDF = [pdfData base64EncodedStringWithOptions:0];
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:base64PDF];
        [self.commandDelegate sendPluginResult:result callbackId:[command callbackId]];
        NSLog(@"[createPDFUsingPrintFormatter] PDF sent as base64.");
    } else {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:outputPath];
        [self.commandDelegate sendPluginResult:result callbackId:[command callbackId]];
        NSLog(@"[createPDFUsingPrintFormatter] PDF path sent: %@", outputPath);
    }

    self.hasPendingOperation = NO;
    NSLog(@"[createPDFUsingPrintFormatter] PDF generation process completed.");
}

@end
