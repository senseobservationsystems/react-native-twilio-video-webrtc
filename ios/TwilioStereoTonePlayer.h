//
//  RCTTWAudioPlayer.h
//  RNTwilioVideoWebRTC
//
//  Created by Umar Nizamani on 29/06/2020.
//

#import <React/RCTBridgeModule.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

// A class to play stereo tones during a Twilio Call
@interface TwilioStereoTonePlayer : NSObject <RCTBridgeModule>

// Class properties

// Maximum number of audio files that can be loaded by this class
@property (nonatomic) int maxLoadableFiles;

// Properties for currently playing file
@property (nonatomic, strong) AVQueuePlayer *currentPlayer;
@property (nonatomic, strong) AVPlayerLooper *playerLooper;
@property (nonatomic, strong) NSString *currentPlayingFile;
@property (nonatomic) float volume;
@property (nonatomic) float playbackSpeed;


@property (nonatomic, strong) NSMutableDictionary *loadedFiles;

- (void)initialize:(int)maxAudioFiles;
- (void)preload:(NSString*)filename resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject;
- (void)play:(NSString*)filename isLooping:(BOOL)isLooping volume:(float)volume playbackSpeed:(float)playbackSpeed resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject;
- (void)pause;
- (void)setVolume:(float)volume;
- (void)release:(NSString*)filename;
- (void)terminate;

@end
