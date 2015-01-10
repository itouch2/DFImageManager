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

#import "DFImageCacheLookupOperation.h"
#import "DFImageCacheStoreOperation.h"
#import "DFImageDeserializer.h"
#import "DFImageFetchConnectionOperation.h"
#import "DFImageRequest.h"
#import "DFImageRequestOptions.h"
#import "DFImageResponse.h"
#import "DFURLImageFetcher.h"
#import "DFURLConnectionOperation.h"
#import "DFURLResponseDeserializing.h"
#import <DFCache/DFCache.h>


@implementation DFURLImageFetcher {
    NSOperationQueue *_queueForFilesystem;
    NSOperationQueue *_queueForNetwork;
}

- (instancetype)initWithCache:(DFCache *)cache {
    if (self = [super init]) {
        _cache = cache;
        
        _queueForFilesystem = [NSOperationQueue new];
        _queueForFilesystem.maxConcurrentOperationCount = 1;
        
        _queueForNetwork = [NSOperationQueue new];
        _queueForNetwork.maxConcurrentOperationCount = 2;
    }
    return self;
}

#pragma mark - <DFImageFetcher>

- (BOOL)canHandleRequest:(DFImageRequest *)request {
    if ([request.asset isKindOfClass:[NSURL class]]) {
        NSURL *URL = request.asset;
        if ([[[self class] supportedSchemes] containsObject:URL.scheme]) {
            return YES;
        }
    }
    return NO;
}

+ (NSSet *)supportedSchemes {
    static NSSet *schemes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        schemes = [NSSet setWithObjects:@"http", @"https", @"ftp", @"file", nil];
    });
    return schemes;
}

- (NSString *)uniqueIDForAsset:(id)asset {
    return [((NSURL *)asset) absoluteString];
}

- (NSArray *)keyPathsAffectingExecutionContextIDForRequest:(DFImageRequest *)request {
    static NSArray *_keyPathsForNetworking;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _keyPathsForNetworking = @[ @"options.cacheStoragePolicy",
                       @"options.networkAccessAllowed" ];
        
    });
    return [self _isFilesystemRequest:request] ? nil : _keyPathsForNetworking;
}

#pragma mark - Subclassing Hooks

- (NSOperation<DFImageManagerOperation> *)createCacheLookupOperationForRequest:(DFImageRequest *)request {
    if (self.cache != nil && ![self _isFilesystemRequest:request]) {
        NSString *assetID = [self uniqueIDForAsset:request.asset];
        return [[DFImageCacheLookupOperation alloc] initWithAssetID:assetID request:request cache:self.cache];
    } else {
        return nil;
    }
}

- (NSOperation<DFImageManagerOperation> *)createImageFetchOperationForRequest:(DFImageRequest *)request {
    if (request.options.networkAccessAllowed || [self _isFilesystemRequest:request]) {
        NSMutableURLRequest *URLRequest = [[NSMutableURLRequest alloc] initWithURL:request.asset cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.f];
        DFImageFetchConnectionOperation *operation = [[DFImageFetchConnectionOperation alloc] initWithRequest:URLRequest];
        operation.deserializer = [DFImageDeserializer new];
        return operation;
    } else {
        return nil;
    }
}

- (NSOperation *)createCacheStoreOperationForRequest:(DFImageRequest *)request previousOperation:(NSOperation<DFImageManagerOperation> *)previousOperation {
    DFImageResponse *response = [previousOperation imageResponse];
    if (self.cache != nil && ![self _isFilesystemRequest:request]) {
        NSString *assetID = [self uniqueIDForAsset:request.asset];
        return [[DFImageCacheStoreOperation alloc] initWithAssetID:assetID request:request response:response cache:self.cache];
    } else {
        return nil;
    }
}

- (NSOperationQueue *)operationQueueForOperation:(NSOperation *)operation {
    if (!operation) {
        return nil;
    }
    if ([operation isKindOfClass:[DFImageCacheLookupOperation class]] ||
        [operation isKindOfClass:[DFImageCacheStoreOperation class]]) {
        return _queueForFilesystem;
    } else {
        return _queueForNetwork;
    }
}

#pragma mark - 

- (BOOL)_isFilesystemRequest:(DFImageRequest *)request {
    return [((NSURL *)request.asset) isFileURL];
}

@end
