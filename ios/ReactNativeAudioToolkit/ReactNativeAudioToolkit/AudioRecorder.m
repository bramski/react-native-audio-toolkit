//
//  AudioManager.m
//  ReactNativeAudioToolkit
//
//  Created by Oskar Vuola on 28/06/16.
//  Copyright (c) 2016 Futurice.
//
//  Licensed under the MIT license. For more information, see LICENSE.

#import "AudioRecorder.h"
#import "RCTEventDispatcher.h"
//#import "RCTEventEmitter"
#import "Helpers.h"

@import AVFoundation;

@interface AudioRecorder () <AVAudioRecorderDelegate>

@property (nonatomic, strong) NSMutableDictionary *recorderPool;

@end

@implementation AudioRecorder

@synthesize bridge = _bridge;

- (void)dealloc {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [audioSession setActive:NO error:&error];
    
    if (error) {
        NSLog (@"RCTAudioRecorder: Could not deactivate current audio session. Error: %@", error);
        return;
    }
}

- (NSMutableDictionary *) recorderPool {
    if (!_recorderPool) {
        _recorderPool = [NSMutableDictionary new];
    }
    return _recorderPool;
}

-(NSNumber *) keyForRecorder:(nonnull AVAudioRecorder*)recorder {
    return [[_recorderPool allKeysForObject:recorder] firstObject];
}

#pragma mark - React exposed functions

RCT_EXPORT_MODULE();


RCT_EXPORT_METHOD(prepare:(nonnull NSNumber *)recorderId withPath:(NSString * _Nullable)path withOptions:(NSDictionary *)options withCallback:(RCTResponseSenderBlock)callback) {
    if ([path length] == 0) {
        NSDictionary* dict = [Helpers errObjWithCode:@"nopath" withMessage:@"Provided path was empty"];
        callback(@[dict]);
        return;
    } else if ([[self recorderPool] objectForKey:recorderId]) {
        NSDictionary* dict = [Helpers errObjWithCode:@"invalidid" withMessage:@"Recorder with that id already exists"];
        callback(@[dict]);
        return;
    }
    
    NSURL *url;
    
    NSString *bundlePath = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] bundlePath], path];
    
    url = [NSURL URLWithString:[bundlePath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    
    // Initialize audio session
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [audioSession setCategory:AVAudioSessionCategoryRecord error:&error];
    if (error) {
        NSDictionary* dict = [Helpers errObjWithCode:@"initfail" withMessage:@"Failed to set audio session category"];
        callback(@[dict]);
        
        return;
    }
    
    // Set audio session active
    [audioSession setActive:YES error:&error];
    if (error) {
        NSDictionary* dict = [Helpers errObjWithCode:@"initfail" withMessage:@"Could not set audio session active"];
        callback(@[dict]);
        
        return;
    }
    
    // Settings for the recorder
    NSDictionary *recordSetting = [Helpers recorderSettingsFromOptions:options];
    
    // Initialize a new recorder
    AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:url settings:recordSetting error:&error];
    if (error) {
        NSDictionary* dict = [Helpers errObjWithCode:@"initfail" withMessage:@"Failed to initialize recorder"];
        callback(@[dict]);
        return;
        
        return;
    } else if (!recorder) {
        NSDictionary* dict = [Helpers errObjWithCode:@"initfail" withMessage:@"Failed to initialize recorder"];
        callback(@[dict]);
        
        return;
    }
    recorder.delegate = self;
    [[self recorderPool] setObject:recorder forKey:recorderId];
    
    BOOL success = [recorder prepareToRecord];
    if (!success) {
        [self destroyRecorderWithId:recorderId];
        NSDictionary* dict = [Helpers errObjWithCode:@"preparefail" withMessage:@"Failed to prepare recorder"];
        callback(@[dict]);
        return;
    }
    
    callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(record:(nonnull NSNumber *)recorderId withCallback:(RCTResponseSenderBlock)callback) {
    AVAudioRecorder *recorder = [[self recorderPool] objectForKey:recorderId];
    if (recorder) {
        if (![recorder record]) {
            NSDictionary* dict = [Helpers errObjWithCode:@"preparefail" withMessage:@"Failed to start recorder"];
            callback(@[dict]);
            return;
        }
    } else {
        NSDictionary* dict = [Helpers errObjWithCode:@"notfound" withMessage:@"Recorder with that id was not found"];
        callback(@[dict]);
        return;
    }
    callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(stop:(nonnull NSNumber *)recorderId withCallback:(RCTResponseSenderBlock)callback) {
    AVAudioRecorder *recorder = [[self recorderPool] objectForKey:recorderId];
    if (recorder) {
        [recorder stop];
    } else {
        NSDictionary* dict = [Helpers errObjWithCode:@"notfound" withMessage:@"Recorder with that id was not found"];
        callback(@[dict]);
        return;
    }
    callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(destroy:(nonnull NSNumber *)recorderId withCallback:(RCTResponseSenderBlock)callback) {
    [self destroyRecorderWithId:recorderId];
    callback(@[[NSNull null]]);
}

#pragma mark - Delegate methods
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *) aRecorder successfully:(BOOL)flag {
    if ([[_recorderPool allValues] containsObject:aRecorder]) {
        NSNumber *recordId = [self keyForRecorder:aRecorder];
        [[self recorderPool] removeObjectForKey:recordId];
        NSLog (@"RCTAudioRecorder: Recording finished, successful: %d", flag);
        NSString *eventName = [NSString stringWithFormat:@"RCTAudioRecorder:%@", recordId];
        [self.bridge.eventDispatcher sendAppEventWithName:eventName
                                                        body:@{@"event" : @"ended",
                                                               @"data" : [NSNull null]
                                                               }];
    }
  
}

- (void)destroyRecorderWithId:(NSNumber *)recorderId {
    if ([[[self recorderPool] allKeys] containsObject:recorderId]) {
        AVAudioRecorder *recorder = [[self recorderPool] objectForKey:recorderId];
        [recorder stop];
        if (recorder) {
            [[self recorderPool] removeObjectForKey:recorderId];
        }
    }
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder
                                   error:(NSError *)error {
    NSNumber *recordId = [self keyForRecorder:recorder];
    
    [self destroyRecorderWithId:recordId];
    NSString *eventName = [NSString stringWithFormat:@"RCTAudioRecorder:%@", recordId];
    [self.bridge.eventDispatcher sendAppEventWithName:eventName
                                               body:@{@"event": @"error",
                                                      @"data" : [error description]
                                                      }];
}

@end
