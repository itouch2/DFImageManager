// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "DFImageRequest.h"
#import "DFImageRequestOptions.h"
#import "DFImageResponse.h"
#import "DFURLHTTPImageDeserializer.h"
#import "DFURLImageDeserializer.h"
#import "DFURLImageFetcher.h"
#import "DFURLImageRequestOptions.h"
#import "DFURLResponseDeserializing.h"
#import "DFURLSessionOperation.h"

NSString *const DFImageInfoURLResponseKey = @"DFImageInfoURLResponseKey";


@interface _DFURLSessionDataTaskHandler : NSObject

@property (nonatomic, copy, readonly) DFURLSessionProgressHandler progressHandler;
@property (nonatomic, copy, readonly) DFURLSessionCompletionHandler completionHandler;
@property (nonatomic, readonly) NSMutableData *data;

- (instancetype)initWithProgressHandler:(DFURLSessionProgressHandler)progressHandler completion:(DFURLSessionCompletionHandler)completion;

@end

@implementation _DFURLSessionDataTaskHandler

- (instancetype)initWithProgressHandler:(DFURLSessionProgressHandler)progressHandler completion:(DFURLSessionCompletionHandler)completionHandler {
    if (self = [super init]) {
        _progressHandler = [progressHandler copy];
        _completionHandler = [completionHandler copy];
        _data = [NSMutableData new];
    }
    return self;
}

@end


@interface DFURLImageFetcher () <DFURLSessionOperationDelegate>

@end

@implementation DFURLImageFetcher {
    NSOperationQueue *_queue;
    NSMutableDictionary *_sessionTaskHandlers;
}

- (instancetype)initWithSession:(NSURLSession *)session sessionDelegate:(id<DFURLImageFetcherSessionDelegate>)sessionDelegate {
    NSParameterAssert(session);
    NSParameterAssert(sessionDelegate);
    if (self = [super init]) {
        _session = session;
        _sessionDelegate = sessionDelegate;
        _sessionTaskHandlers = [NSMutableDictionary new];
        _sessionTaskHandlers = nil;
        
        // We don't need to limit concurrent operations for NSURLSession. For more info see https://github.com/kean/DFImageManager/wiki/Image-Caching-Guide
        _queue = [NSOperationQueue new];
        
        _supportedSchemes = [NSSet setWithObjects:@"http", @"https", @"ftp", @"file", @"data", nil];
    }
    return self;
}

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    NSParameterAssert(configuration);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    return [self initWithSession:session sessionDelegate:self];
}

#pragma mark - <DFImageFetching>

- (BOOL)canHandleRequest:(DFImageRequest *)request {
    if ([request.resource isKindOfClass:[NSURL class]]) {
        if ([self.supportedSchemes containsObject:((NSURL *)request.resource).scheme]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isRequestFetchEquivalent:(DFImageRequest *)request1 toRequest:(DFImageRequest *)request2 {
    if (![self isRequestCacheEquivalent:request1 toRequest:request2]) {
        return NO;
    }
    DFURLImageRequestOptions *options1 = (id)request1.options;
    DFURLImageRequestOptions *options2 = (id)request2.options;
    return (options1.allowsNetworkAccess == options2.allowsNetworkAccess &&
            options1.cachePolicy == options2.cachePolicy);
}

- (BOOL)isRequestCacheEquivalent:(DFImageRequest *)request1 toRequest:(DFImageRequest *)request2 {
    if (request1 == request2) {
        return YES;
    }
    NSURL *URL1 = (NSURL *)request1.resource;
    NSURL *URL2 = (NSURL *)request2.resource;
    return [URL1 isEqual:URL2];
}

- (DFImageRequest *)canonicalRequestForRequest:(DFImageRequest *)request {
    if (!request.options || ![request.options isKindOfClass:[DFURLImageRequestOptions class]]) {
        DFURLImageRequestOptions *options = [[DFURLImageRequestOptions alloc] initWithOptions:request.options];
        request.options = options;
    }
    return request;
}

- (NSOperation *)startOperationWithRequest:(DFImageRequest *)request progressHandler:(void (^)(double))progressHandler completion:(void (^)(DFImageResponse *))completion {
    DFURLSessionOperation *operation = [self _createOperationForImageRequest:request];
    operation.delegate = self;
    [_queue addOperation:operation];
    return operation;
}

- (DFURLSessionOperation *)_createOperationForImageRequest:(DFImageRequest *)imageRequest {
    NSURL *URL = (NSURL *)imageRequest.resource;
    NSURLRequest *URLRequest = [NSURLRequest requestWithURL:URL];
    DFURLSessionOperation *operation = [self _operationForImageRequest:imageRequest URLRequest:URLRequest];
    operation.deserializer = [self _responseDeserializerForImageRequest:imageRequest URLRequest:URLRequest];
    return operation;
}

- (DFURLSessionOperation *)_operationForImageRequest:(DFImageRequest *)imageRequest URLRequest:(NSURLRequest *)URLRequest {
    if ([self.delegate respondsToSelector:@selector(URLImageFetcher:operationForImageRequest:URLRequest:)]) {
        return [self.delegate URLImageFetcher:self operationForImageRequest:imageRequest URLRequest:URLRequest];
    }
    return [[DFURLSessionOperation alloc] initWithRequest:URLRequest];
}

- (id<DFURLResponseDeserializing>)_responseDeserializerForImageRequest:(DFImageRequest *)imageRequest URLRequest:(NSURLRequest *)URLRequest {
    if ([self.delegate respondsToSelector:@selector(URLImageFetcher:responseDeserializerForImageRequest:URLRequest:)]) {
        return [self.delegate URLImageFetcher:self responseDeserializerForImageRequest:imageRequest URLRequest:URLRequest];
    }
    if ([URLRequest.URL.scheme hasPrefix:@"http"]) {
        return [DFURLHTTPImageDeserializer new];
    } else {
        return [DFURLImageDeserializer new];
    }
}

#pragma mark - <NSURLSessionDataTaskDelegate>

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    // Do nothung
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    // Do nothing
}

#pragma mark - <DFURLSessionOperationDelegate>

- (NSURLSessionDataTask *)URLSessionOperation:(DFURLSessionOperation *)operation dataTaskWithRequest:(NSURLRequest *)request progressHandler:(DFURLSessionProgressHandler)progressHandler completionHandler:(DFURLSessionCompletionHandler)completionHandler {
    return [self.sessionDelegate URLImageFetcher:self dataTaskWithRequest:request progressHandler:progressHandler completionHandler:completionHandler];
}

#pragma mark - <DFURLImageFetcherSessionDelegate>

- (NSURLSessionDataTask *)URLImageFetcher:(DFURLImageFetcher *)fetcher dataTaskWithRequest:(NSURLRequest *)request progressHandler:(DFURLSessionProgressHandler)progressHandler completionHandler:(DFURLSessionCompletionHandler)completionHandler {
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request];
    return task;
}

@end
