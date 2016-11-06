//
//  FirstViewController.m
//  OSS_Test
//
//  Created by lxm on 2016/11/4.
//  Copyright © 2016年 lxm. All rights reserved.
//

#import "FirstViewController.h"
#import <AliyunOSSiOS/OSSService.h>
#import <CommonCrypto/CommonDigest.h>

NSString * const AccessKey = @"";
NSString * const SecretKey = @"";
NSString * const endPoint = @"http://oss-cn-shenzhen.aliyuncs.com";
NSString * const multipartUploadKey = @"multipartUploadObject";

@interface FirstViewController ()

@end

@implementation FirstViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self initOSSClient];
    [self uploadObjectAsync];
//    [self listObjectsInBucket];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)initOSSClient {
    
    id<OSSCredentialProvider> credential = [[OSSPlainTextAKSKPairCredentialProvider alloc] initWithPlainTextAccessKey:AccessKey
                                                                                                            secretKey:SecretKey];
    
    // 自实现签名，可以用本地签名也可以远程加签
    id<OSSCredentialProvider> credential1 = [[OSSCustomSignerCredentialProvider alloc] initWithImplementedSigner:^NSString *(NSString *contentToSign, NSError *__autoreleasing *error) {
        NSString *signature = [OSSUtil calBase64Sha1WithData:contentToSign withSecret:@"<your secret key>"];
        if (signature != nil) {
            *error = nil;
        } else {
            // construct error object
            *error = [NSError errorWithDomain:@"<your error domain>" code:OSSClientErrorCodeSignFailed userInfo:nil];
            return nil;
        }
        return [NSString stringWithFormat:@"OSS %@:%@", @"<your access key>", signature];
    }];
    
    // Federation鉴权，建议通过访问远程业务服务器获取签名
    // 假设访问业务服务器的获取token服务时，返回的数据格式如下：
    // {"accessKeyId":"STS.iA645eTOXEqP3cg3VeHf",
    // "accessKeySecret":"rV3VQrpFQ4BsyHSAvi5NVLpPIVffDJv4LojUBZCf",
    // "expiration":"2015-11-03T09:52:59Z[;",
    // "federatedUser":"335450541522398178:alice-001",
    // "requestId":"C0E01B94-332E-4582-87F9-B857C807EE52",
    // "securityToken":"CAES7QIIARKAAZPlqaN9ILiQZPS+JDkS/GSZN45RLx4YS/p3OgaUC+oJl3XSlbJ7StKpQp1Q3KtZVCeAKAYY6HYSFOa6rU0bltFXAPyW+jvlijGKLezJs0AcIvP5a4ki6yHWovkbPYNnFSOhOmCGMmXKIkhrRSHMGYJRj8AIUvICAbDhzryeNHvUGhhTVFMuaUE2NDVlVE9YRXFQM2NnM1ZlSGYiEjMzNTQ1MDU0MTUyMjM5ODE3OCoJYWxpY2UtMDAxMOG/g7v6KToGUnNhTUQ1QloKATEaVQoFQWxsb3cSHwoMQWN0aW9uRXF1YWxzEgZBY3Rpb24aBwoFb3NzOioSKwoOUmVzb3VyY2VFcXVhbHMSCFJlc291cmNlGg8KDWFjczpvc3M6KjoqOipKEDEwNzI2MDc4NDc4NjM4ODhSAFoPQXNzdW1lZFJvbGVVc2VyYABqEjMzNTQ1MDU0MTUyMjM5ODE3OHIHeHljLTAwMQ=="}
    id<OSSCredentialProvider> credential2 = [[OSSFederationCredentialProvider alloc] initWithFederationTokenGetter:^OSSFederationToken * {
        NSURL * url = [NSURL URLWithString:@"http://localhost:8080/distribute-token.json"];
        NSURLRequest * request = [NSURLRequest requestWithURL:url];
        OSSTaskCompletionSource * tcs = [OSSTaskCompletionSource taskCompletionSource];
        NSURLSession * session = [NSURLSession sharedSession];
        NSURLSessionTask * sessionTask = [session dataTaskWithRequest:request
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                        if (error) {
                                                            [tcs setError:error];
                                                            return;
                                                        }
                                                        [tcs setResult:data];
                                                    }];
        [sessionTask resume];
        [tcs.task waitUntilFinished];
        if (tcs.task.error) {
            NSLog(@"get token error: %@", tcs.task.error);
            return nil;
        } else {
            NSDictionary * object = [NSJSONSerialization JSONObjectWithData:tcs.task.result
                                                                    options:kNilOptions
                                                                      error:nil];
            OSSFederationToken * token = [OSSFederationToken new];
            token.tAccessKey = [object objectForKey:@"accessKeyId"];
            token.tSecretKey = [object objectForKey:@"accessKeySecret"];
            token.tToken = [object objectForKey:@"securityToken"];
            token.expirationTimeInGMTFormat = [object objectForKey:@"expiration"];
            NSLog(@"get token: %@", token);
            return token;
        }
    }];
    
    
    OSSClientConfiguration * conf = [OSSClientConfiguration new];
    conf.maxRetryCount = 2;
    conf.timeoutIntervalForRequest = 30;
    conf.timeoutIntervalForResource = 24 * 60 * 60;
    
    client = [[OSSClient alloc] initWithEndpoint:endPoint credentialProvider:credential clientConfiguration:conf];
}

- (NSString *)genTimeStamp
{
    return [NSString stringWithFormat:@"%d", (int)[[NSDate date] timeIntervalSince1970]];
}

/**
 *  生成随机数
 *
 *  @return NSString
 */
- (NSString *)randomK
{
    int randomIndex = arc4random()%1000;
    NSString *randomString = [self md5:[NSString stringWithFormat:@"%d", randomIndex]];
    
    NSMutableString *k = [[NSMutableString alloc] init];
    for (int i = 0; i < 4; i++) {
        int j = arc4random()%31;
        NSRange range = NSMakeRange(j, 1);
        k = [NSMutableString stringWithString:[k stringByAppendingString:[randomString substringWithRange:range]]];
    }
    
    return k;
}

/**
 *  md5
 *
 *
 *  @return NSString
 */
- (NSString *)md5:(NSString *)str {
    const char *cStr = [str UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, (unsigned long)strlen(cStr), digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [result appendFormat:@"%02x", digest[i]];
    return result;
}

// 异步上传
- (void)uploadObjectAsync {
    OSSPutObjectRequest * put = [OSSPutObjectRequest new];
    NSString *imagePath = [[NSBundle mainBundle] pathForResource:@"123" ofType:@"mp4"];
    put.uploadingFileURL = [NSURL fileURLWithPath:imagePath];

    // required fields
    put.bucketName = @"qingliang";
    put.objectKey = [NSString stringWithFormat:@"ios_%@_%@.%@",[self genTimeStamp],[self randomK],put.uploadingFileURL.pathExtension];
    
    // optional fields
    put.uploadProgress = ^(int64_t bytesSent, int64_t totalByteSent, int64_t totalBytesExpectedToSend) {
        NSLog(@"%lld, %lld, %lld", bytesSent, totalByteSent, totalBytesExpectedToSend);
    };
    put.contentType = put.uploadingFileURL.pathExtension;
    put.contentMd5 = @"";
    put.contentEncoding = @"";
    put.contentDisposition = @"";
    
    OSSTask * putTask = [client putObject:put];
    
    [putTask continueWithBlock:^id(OSSTask *task) {
        NSLog(@"objectKey: %@", put.objectKey);
        if (!task.error) {
            NSString *strUrl = [endPoint stringByReplacingOccurrencesOfString:@"http://" withString:@""];
            NSString *urlStr = [NSString stringWithFormat:@"http://%@.%@/%@",put.bucketName,strUrl,put.objectKey];
            NSLog(@"upload object success!url=%@",urlStr);
            
        } else {
            NSLog(@"upload object failed, error: %@" , task.error);
        }
        return nil;
    }];
    
}

- (void)listObjectsInBucket {
    OSSGetBucketRequest * getBucket = [OSSGetBucketRequest new];
    getBucket.bucketName = @"qingliang";
    getBucket.delimiter = @"";
    getBucket.prefix = @"";
    
    
    OSSTask * getBucketTask = [client getBucket:getBucket];
    
    [getBucketTask continueWithBlock:^id(OSSTask *task) {
        if (!task.error) {
            OSSGetBucketResult * result = task.result;
            NSLog(@"get bucket success!");
            for (NSDictionary * objectInfo in result.contents) {
                NSLog(@"list object: %@", objectInfo);
            }
        } else {
            NSLog(@"get bucket failed, error: %@", task.error);
        }
        return nil;
    }];
}

@end
