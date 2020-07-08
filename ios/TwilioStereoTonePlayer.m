//
//  RCTTWAudioPlayer.m
//  RNTwilioVideoWebRTC
//
//  Created by Umar Nizamani on 29/06/2020.
//

#import "TwilioStereoTonePlayer.h"
 
@implementation TwilioStereoTonePlayer

-(id)init {
    _volume = 1.0f;
    _playbackSpeed = 1.0f;
    return self;
}

static RCTTWCustomAudioDevice *_audioDevice;

+ ( RCTTWCustomAudioDevice *)audioDevice {
   if (_audioDevice==nil) {
      [TwilioStereoTonePlayer setAudioDevice:_audioDevice];
   }
   return _audioDevice;
}

+ (void)setAudioDevice:(RCTTWCustomAudioDevice *)audioDevice {
    _audioDevice = audioDevice;
}


RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(initialize:(int)maxLoadableFiles) {
    _maxLoadableFiles = maxLoadableFiles;
    _loadedFiles = [[NSMutableDictionary alloc]initWithCapacity:maxLoadableFiles];
}

RCT_EXPORT_METHOD(preload:(NSString*)filename resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"preload %@", filename);
    
    NSError *err;
    
    // Sanity Check
    if (_loadedFiles == NULL) {
        reject(@"Error", [NSString stringWithFormat:@"Please call initialize first"], err);
        return;
    }
    
    if ([_loadedFiles count] >= _maxLoadableFiles) {
        reject(@"Error", [NSString stringWithFormat:@"Trying to load more files than you called initialize with! Already loaded %i files", _maxLoadableFiles], err);
        return;
    }
    
    // If we have already loaded this file then just instantly resolve the promise to be true
    if ([_loadedFiles objectForKey:filename] != NULL) {
        resolve(@(true));
        return;
    }

    // Create a file path based on the local bundle as we only expect to play files that are locally on disk
    NSString *filepath = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] bundlePath], filename];
    
    // Make sure the path is escaped correctly and only has strings that are supported in a file path
    NSCharacterSet *set = [NSCharacterSet URLFragmentAllowedCharacterSet];
    NSString * filepathEscaped = [filepath stringByAddingPercentEncodingWithAllowedCharacters:set];

    // Create a local file URL
    NSURL *url = [NSURL fileURLWithPath:filepath];
    
    // Try to load the AVAudio File
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&err];
    if (err != NULL) {
        reject(@"Error", [NSString stringWithFormat:@"Failed to load file at path: %@", filepathEscaped], err);
        return;
    }
    
    // Create an audio buffer to read the file into
    AVAudioPCMBuffer *musicBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat
                                                 frameCapacity:(AVAudioFrameCount)file.length];

    // Lets try to load the file into an audio buffer
    BOOL success = [file readIntoBuffer:musicBuffer error:&err];
    if (!success) {
        reject(@"Error", [NSString stringWithFormat:@"Failed to read file into audio buffer at path: %@", filepathEscaped], err);
        return;
    }
    
    [_loadedFiles setObject:musicBuffer forKey:filename];

    resolve(@(true));
}

RCT_EXPORT_METHOD(play:(NSString*)filename isLooping:(BOOL)isLooping volume:(float)volume playbackSpeed:(float)playbackSpeed resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"play %@ - volume %f - isLooping %s", filename, volume, isLooping ? "Yes" : "No");
    
    NSError *err;
    
    // Sanity Check
    if (_loadedFiles == NULL) {
        reject(@"Error", [NSString stringWithFormat:@"Please call initialize first"], err);
        return;
    }
    
    if (TwilioStereoTonePlayer.audioDevice == nil) {
        reject(@"Error", [NSString stringWithFormat:@"No Custom Audio device found! Are you trying to call play before the Twilio Local Audio Track is created or running in no custom device mode?"], err);
        return;
    }
    
    // Try to load the preloaded player from the loaded players list
    AVAudioPCMBuffer* fileToPlay = [_loadedFiles objectForKey:filename];
    
    // If the current file is not already loaded
    if (fileToPlay == nil) {
        
        // Then make sure we load the file first
        [self preload:filename resolver:resolve rejecter:reject];
        
        fileToPlay = [_loadedFiles objectForKey:filename];
        
        // If we still can't find the file, then there was probably an error loading the file.
        // We will instantly return as we expect preload to already have called the rejection promise.
        if (fileToPlay == nil) {
            return;
        }
    }

    // Before we play a new tone, lets make sure we pause any tone that is currently playing
    [self pause];
    
    // Try to schedule playback on the Twilio Custom Audio Device
    [[TwilioStereoTonePlayer audioDevice] playBuffer:fileToPlay isLooping:isLooping volume:volume playbackSpeed:playbackSpeed];
    
    _volume = volume;
    _playbackSpeed = playbackSpeed;
    _currentPlayingFile = filename;
    
    resolve(@(true));
}

RCT_EXPORT_METHOD(pause) {
    NSLog(@"pause");
    
    if (TwilioStereoTonePlayer.audioDevice == nil) {
        NSLog(@"Error: No Custom Audio device found! Are you trying to call pause before the Twilio Local Audio Track is created or running in no custom device mode?");
        return;
    }
    
    [[TwilioStereoTonePlayer audioDevice] pausePlayback];
}

RCT_EXPORT_METHOD(setVolume:(float)volume) {
    NSLog(@"setVolume %f", volume);
    
    _volume = volume;
    
    if (TwilioStereoTonePlayer.audioDevice == nil) {
        NSLog(@"Error: No Custom Audio device found! Are you trying to call setVolume before the Twilio Local Audio Track is created or running in no custom device mode?");
        return;
    }
    
    [[TwilioStereoTonePlayer audioDevice] setPlaybackVolume:volume];
}

RCT_EXPORT_METHOD(setPlaybackSpeed:(float)playbackSpeed) {
    NSLog(@"setPlaybackSpeed %f", playbackSpeed);
    
    _playbackSpeed = playbackSpeed;
    
    if (TwilioStereoTonePlayer.audioDevice == nil) {
        NSLog(@"Error: No Custom Audio device found! Are you trying to call setPlaybackSpeed before the Twilio Local Audio Track is created or running in no custom device mode?");
        return;
    }
    
    [[TwilioStereoTonePlayer audioDevice] setPlaybackSpeed:playbackSpeed];
}

RCT_EXPORT_METHOD(release:(NSString*)filename) {
    NSLog(@"release %@", filename);
    
    if (_loadedFiles) {
        [_loadedFiles removeObjectForKey:filename];
    }
}

RCT_EXPORT_METHOD(terminate) {
    NSLog(@"terminate");
    
    if (_loadedFiles) {
        [_loadedFiles removeAllObjects];

        // We don't need to delete objectives in objective C as ARC will take care of unreferenced objects
        _loadedFiles = NULL;
    }
}


@end
