//
//  RCTTWCustomAudioDevice.h
//  react-native-twilio-video-webrtc
//
//  Created by Umar Nizamani on 29/06/2020.
//

#import <TwilioVideo/TwilioVideo.h>

NS_CLASS_AVAILABLE(NA, 11_0)
@interface RCTTWCustomAudioDevice : NSObject <TVIAudioDevice>

- (bool)playBuffer:(AVAudioPCMBuffer*)buffer isLooping:(BOOL)isLooping volume:(float)volume playbackSpeed:(float)playbackSpeed;
- (void)pausePlayback;
- (void)setPlaybackVolume:(float)volume;
- (void)setPlaybackSpeed:(float)playbackSpeed;

- (void)makeStereo:(bool)stereo;

@end
