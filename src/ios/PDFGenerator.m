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

    // Define padding (in points)
    CGFloat padding = 50.0;

    // Get the content size of the web view
    CGSize contentSize = webView.scrollView.contentSize;

    // Log content size for debugging
    NSLog(@"[createPDFFromWebView] Content Size - width: %f, height: %f", contentSize.width, contentSize.height);

    // Calculate the scale factor to fit the content width to the PDF page width (with padding)
    CGFloat scaleFactor = (pdfPageWidth - 2 * padding) / contentSize.width;

    // Calculate the total scaled height of the content
    CGFloat scaledContentHeight = contentSize.height * scaleFactor;

    // Calculate the number of pages required based on the scaled content height
    NSInteger numberOfPages = ceil(scaledContentHeight / (pdfPageHeight - 2 * padding));

    // Log calculated values for debugging
    NSLog(@"[createPDFFromWebView] Scale Factor: %f", scaleFactor);
    NSLog(@"[createPDFFromWebView] Scaled Content Height: %f", scaledContentHeight);
    NSLog(@"[createPDFFromWebView] PDF Page Width: %f", pdfPageWidth);
    NSLog(@"[createPDFFromWebView] Content Width: %f", contentSize.width);
    NSLog(@"[createPDFFromWebView] PDF Page Height: %f", pdfPageHeight);
    NSLog(@"[createPDFFromWebView] Number of Pages: %ld", (long)numberOfPages);

    // Set up the PDF page bounds
    CGRect pdfPageBounds = CGRectMake(0, 0, pdfPageWidth, pdfPageHeight);

    // Begin the PDF context
    NSMutableData *pdfData = [NSMutableData data];
    UIGraphicsBeginPDFContextToData(pdfData, pdfPageBounds, nil);

    // Start processing pages
    [self generatePageForWebView:webView atIndex:0 totalPages:numberOfPages scaleFactor:scaleFactor pdfPageWidth:pdfPageWidth pdfPageHeight:pdfPageHeight pdfPageBounds:pdfPageBounds padding:padding contentSize:contentSize outputPath:outputPath pdfData:pdfData command:command];
}

// Recursive function to generate pages in order
- (void)generatePageForWebView:(WKWebView *)webView atIndex:(NSInteger)pageIndex totalPages:(NSInteger)totalPages scaleFactor:(CGFloat)scaleFactor pdfPageWidth:(CGFloat)pdfPageWidth pdfPageHeight:(CGFloat)pdfPageHeight pdfPageBounds:(CGRect)pdfPageBounds padding:(CGFloat)padding contentSize:(CGSize)contentSize outputPath:(NSString *)outputPath pdfData:(NSMutableData *)pdfData command:(CDVInvokedUrlCommand *)command {

    if (pageIndex >= totalPages) {
        // All pages have been processed, finish the PDF
        UIGraphicsEndPDFContext();

        // Write the PDF to file
        NSLog(@"[generatePageForWebView] PDF creation complete. Writing to file: %@", outputPath);
        BOOL success = [pdfData writeToFile:outputPath atomically:YES];
        if (success) {
            NSLog(@"[generatePageForWebView] PDF successfully written to file.");
        } else {
            NSLog(@"[generatePageForWebView] Error writing PDF to file.");
        }

        // Send back the result
        NSString *option = [command argumentAtIndex:4 withDefault:@"base64"];
        if ([option isEqualToString:@"base64"]) {
            NSString *base64PDF = [pdfData base64EncodedStringWithOptions:0];
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:base64PDF];
            [self.commandDelegate sendPluginResult:result callbackId:[command callbackId]];
            NSLog(@"[generatePageForWebView] PDF sent as base64.");
        } else {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:outputPath];
            [self.commandDelegate sendPluginResult:result callbackId:[command callbackId]];
            NSLog(@"[generatePageForWebView] PDF path sent: %@", outputPath);
        }

        self.hasPendingOperation = NO;
        NSLog(@"[generatePageForWebView] PDF generation process completed.");
        return;
    }

    // Calculate the portion of the webView's content to draw on this page
    CGRect snapshotRect = CGRectMake(0, pageIndex * (pdfPageHeight - 2 * padding) / scaleFactor, contentSize.width, (pdfPageHeight - 2 * padding) / scaleFactor);

    // Log the snapshot rect for debugging
    NSLog(@"[generatePageForWebView] Snapshot Rect for Page %ld: %@", (long)pageIndex, NSStringFromCGRect(snapshotRect));

    WKSnapshotConfiguration *snapshotConfig = [[WKSnapshotConfiguration alloc] init];
    snapshotConfig.rect = snapshotRect;

    // Take a snapshot of the required content portion
    [webView takeSnapshotWithConfiguration:snapshotConfig completionHandler:^(UIImage *snapshotImage, NSError *error) {
        if (!error) {
            // Create a new PDF page
            UIGraphicsBeginPDFPageWithInfo(pdfPageBounds, nil);

            // Calculate the scaled height of the image for this page
            CGFloat imageHeight = snapshotImage.size.height * scaleFactor;

            // Draw the snapshot image into the PDF page bounds with padding
            [snapshotImage drawInRect:CGRectMake(padding, padding, pdfPageWidth - 2 * padding, imageHeight)];

            // After the current page is processed, recursively process the next one
            [self generatePageForWebView:webView atIndex:pageIndex + 1 totalPages:totalPages scaleFactor:scaleFactor pdfPageWidth:pdfPageWidth pdfPageHeight:pdfPageHeight pdfPageBounds:pdfPageBounds padding:padding contentSize:contentSize outputPath:outputPath pdfData:pdfData command:command];
        } else {
            NSLog(@"[generatePageForWebView] Error taking snapshot: %@", error.localizedDescription);
        }
    }];
}


@end
