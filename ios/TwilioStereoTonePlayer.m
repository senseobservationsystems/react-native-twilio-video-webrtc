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
    NSString *filepath = [NSString stringWithFormat:@"file://%@/%@", [[NSBundle mainBundle] bundlePath], filename];
    
    // Make sure the path is escaped correctly and only has strings that are supported in a file path
    NSCharacterSet *set = [NSCharacterSet URLFragmentAllowedCharacterSet];
    NSString * filepathEscaped = [filepath stringByAddingPercentEncodingWithAllowedCharacters:set];

    // Create an AVAsset file from the escaped path
    AVAsset *asset = [AVAsset assetWithURL:[NSURL URLWithString:filepathEscaped]];
    
    // Check if we can read the path provided to AVAsset above
    if (asset.isReadable == FALSE) {
        reject(@"error", [NSString stringWithFormat:@"ERROR: The specified file cannot be read. %@", filepathEscaped], err);
        return;
    }
    
    // Check if we can actually play the media file provided in the path above
    if (asset.playable == FALSE) {
        reject(@"error", [NSString stringWithFormat:@"ERROR: The specified file at path is unplayable. %@", filepathEscaped], err);
        return;
    }
    
    // We need to make an AVPlayerItem and pass it to an AVQueuePlayer to actually play
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
//    AVQueuePlayer* queuePlayer = [AVQueuePlayer queuePlayerWithItems:@[playerItem]];
    
    if (_currentPlayer == NULL) {
        _currentPlayer = [AVQueuePlayer queuePlayerWithItems:@[playerItem]];
    }
    
    // Set the current file in the loadedFiles array
    [_loadedFiles setObject:playerItem forKey:filename];

    resolve(@(true));
}

RCT_EXPORT_METHOD(play:(NSString*)filename isLooping:(BOOL)isLooping volume:(float)volume playbackSpeed:(float)playbackSpeed resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"play %@ - volume %f - isLooping %s", filename, volume, isLooping ? "Yes" : "No");
    
    // Sanity Check
    if (_loadedFiles == NULL) {
        reject(@"Error", [NSString stringWithFormat:@"Please call initialize first"], NULL);
        return;
    }
    
    // Try to load the preloaded player from the loaded players list
    AVPlayerItem* fileToPlay = [_loadedFiles objectForKey:filename];
    
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
    
    if (_currentPlayer == NULL) {
        reject(@"Error", [NSString stringWithFormat:@"The player is still unitialized! This should be impossible"], NULL);
        return;
    }
    
    // This is an extra safety layer to avoid potential crashes happening from _currentPlayer being NULL
    if (fileToPlay) {
        
        // Recreate the current player with the new item to play
        [_currentPlayer removeAllItems];
        [_currentPlayer insertItem:fileToPlay afterItem:NULL];
        
        // We generate a looper class to tell AVQueuePlayer to loop this file, this ensures better quality looping
        if (isLooping) {
            // TODO: I still don't like this object instantiation in the play method, but I don't see a clean memory efficient way to avoid it for now
            _playerLooper = [AVPlayerLooper playerLooperWithPlayer:_currentPlayer templateItem:fileToPlay];
        }
        
        _volume = volume;
        _playbackSpeed = playbackSpeed;
        
        _currentPlayingFile = filename;
        [_currentPlayer setVolume:_volume];
        [_currentPlayer play];
        
        // NOTE: Always call this AFTER play. Play resets the plaback speed to 1.0
        [_currentPlayer setRate:_playbackSpeed];
        
        NSLog(@"Playing File");
    } else {
        reject(@"error", [NSString stringWithFormat:@"Unable to load file %@", filename], NULL);
    }
    
    resolve(@(true));
}

RCT_EXPORT_METHOD(pause) {
    NSLog(@"pause");
    
    if (_currentPlayer) {
        [_currentPlayer pause];
    }
}

RCT_EXPORT_METHOD(setVolume:(float)volume) {
    NSLog(@"setVolume %f", volume);
    
    _volume = volume;
    if (_currentPlayer) {
        [_currentPlayer setVolume:volume];
    }
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
