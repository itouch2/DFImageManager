//
//  TDFImageManager.m
//  DFImageManager
//
//  Created by Alexander Grebenyuk on 12/26/14.
//  Copyright (c) 2014 Alexander Grebenyuk. All rights reserved.
//

#import "DFImageManagerKit.h"
#import "TDFTesting.h"
#import <OHHTTPStubs/OHHTTPStubs.h>
#import <XCTest/XCTest.h>


@interface TDFImageManager : XCTestCase

@end

@implementation TDFImageManager {
    id<DFImageManager> _imageManager;
}

- (void)setUp {
    [super setUp];

    id<DFImageManagerConfiguration> configuration = [[DFNetworkImageManagerConfiguration alloc] initWithCache:nil];
    _imageManager = [[DFImageManager alloc] initWithConfiguration:configuration imageProcessor:nil cache:nil];
}

- (void)tearDown {
    [super tearDown];
    
    [OHHTTPStubs removeAllStubs];
}

#pragma mark - Smoke Tests

- (void)testThatImageManagerWorks {
    NSString *imageURL = @"test://imagemanager.com/image.jpg";
    [TDFTesting stubRequestWithURL:imageURL];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"image_fetched"];
    
    [_imageManager requestImageForAsset:imageURL targetSize:DFImageManagerMaximumSize contentMode:DFImageContentModeDefault options:nil completion:^(UIImage *image, NSDictionary *info) {
        XCTAssertNotNil(image);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:3.0 handler:nil];
}

- (void)testThatImageManagerHandlesErrors {
    NSString *imageURL = @"test://imagemanager.com/image.jpg";
    
    [OHHTTPStubs stubRequestsPassingTest:^BOOL(NSURLRequest *request) {
        return [request.URL.absoluteString isEqualToString:imageURL];
    } withStubResponse:^OHHTTPStubsResponse *(NSURLRequest *request) {
        return [OHHTTPStubsResponse responseWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
    }];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"fetch_failed"];
    
    [_imageManager requestImageForAsset:imageURL targetSize:DFImageManagerMaximumSize contentMode:DFImageContentModeDefault options:nil completion:^(UIImage *image, NSDictionary *info) {
        NSError *error = info[DFImageInfoErrorKey];
        XCTAssertTrue([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorNotConnectedToInternet);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:3.0 handler:nil];
}

@end
