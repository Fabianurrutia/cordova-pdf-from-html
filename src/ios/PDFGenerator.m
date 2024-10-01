#import "PDFGenerator.h"
#import <objc/runtime.h>  // Import the Objective-C runtime

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

    // Log HTML content
    [webView evaluateJavaScript:@"document.documentElement.outerHTML.toString()" completionHandler:^(id result, NSError *error) {
        if (!error) {
            NSLog(@"[WebView] HTML content loaded: %@", result);

            // Ensure content is fully loaded before creating the PDF
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self createPDFFromWebView:webView outputFile:outputPath command:command];
            });
        } else {
            NSLog(@"[WebView] Failed to retrieve HTML content: %@", error.localizedDescription);
        }
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

- (void)createPDFFromWebView:(WKWebView*)webView outputFile:(NSString*)outputPath command:(CDVInvokedUrlCommand*)command {
    NSLog(@"[createPDFFromWebView] Creating PDF from content...");

    // Standard A4 page size in points (72 DPI)
    CGFloat pdfPageWidth = 595.0;  // A4 width in points
    CGFloat pdfPageHeight = 842.0; // A4 height in points

    // Get the content size of the web view
    CGSize contentSize = webView.scrollView.contentSize;

    // Calculate scale factor to fit content to A4 width
    CGFloat scaleFactor = pdfPageWidth / contentSize.width;
    CGFloat scaledHeight = contentSize.height * scaleFactor;

    // Set up the PDF page bounds with the scaled height
    CGRect pdfPageBounds = CGRectMake(0, 0, pdfPageWidth, scaledHeight);

    WKSnapshotConfiguration *snapshotConfig = [[WKSnapshotConfiguration alloc] init];
    snapshotConfig.rect = CGRectMake(0, 0, contentSize.width, contentSize.height);

    [webView takeSnapshotWithConfiguration:snapshotConfig completionHandler:^(UIImage *snapshotImage, NSError *error) {
        if (error) {
            NSLog(@"[createPDFFromWebView] Error taking snapshot: %@", error.localizedDescription);
            return;
        }

        // Generate PDF from the snapshot image
        NSMutableData *pdfData = [NSMutableData data];
        UIGraphicsBeginPDFContextToData(pdfData, pdfPageBounds, nil);
        UIGraphicsBeginPDFPageWithInfo(pdfPageBounds, nil);

        // Draw the snapshot image into the scaled PDF page bounds
        [snapshotImage drawInRect:CGRectMake(0, 0, pdfPageWidth, scaledHeight)];
        UIGraphicsEndPDFContext();

        NSLog(@"[createPDFFromWebView] PDF creation complete. Writing to file: %@", outputPath);

        // Write the PDF to file
        BOOL success = [pdfData writeToFile:outputPath atomically:YES];
        if (success) {
            NSLog(@"[createPDFFromWebView] PDF successfully written to file.");
        } else {
            NSLog(@"[createPDFFromWebView] Error writing PDF to file.");
        }

        // Send back as base64 or file path based on options
        NSString *option = [command argumentAtIndex:4 withDefault:@"base64"];
        if ([option isEqualToString:@"base64"]) {
            NSString *base64PDF = [pdfData base64EncodedStringWithOptions:0];
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:base64PDF];
            [self.commandDelegate sendPluginResult:result callbackId:[command callbackId]];
            NSLog(@"[createPDFFromWebView] PDF sent as base64.");
        } else {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:outputPath];
            [self.commandDelegate sendPluginResult:result callbackId:[command callbackId]];
            NSLog(@"[createPDFFromWebView] PDF path sent: %@", outputPath);
        }

        self.hasPendingOperation = NO;
        NSLog(@"[createPDFFromWebView] PDF generation process completed.");
    }];
}


@end
