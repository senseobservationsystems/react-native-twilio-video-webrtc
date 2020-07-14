//
//  RCTTWCustomAudioDevice.m
//  react-native-twilio-video-webrtc
//
//  Created by Umar Nizamani on 29/06/2020.
//  Based on ExampleAVAudioEngineDevice from Twilio Video Quickstart Audio Device Example
//

#import "RCTTWCustomAudioDevice.h"

// We want to get as close to 10 msec buffers as possible because this is what the media engine prefers.
static double const kPreferredIOBufferDuration = 0.01;

// We will use mono playback and recording where available.
static size_t const kPreferredNumberOfChannels = 2;

// An audio sample is a signed 16-bit integer.
static size_t const kAudioSampleSize = 2;

static uint32_t const kPreferredSampleRate = 48000;

/*
 * Calls to AudioUnitInitialize() can fail if called back-to-back after a format change or adding and removing tracks.
 * A fall-back solution is to allow multiple sequential calls with a small delay between each. This factor sets the max
 * number of allowed initialization attempts.
 */
static const int kMaxNumberOfAudioUnitInitializeAttempts = 5;

// Audio renderer contexts used in core audio's playout callback to retrieve the sdk's audio device context.
typedef struct AudioRendererContext {
    // Audio device context received in AudioDevice's `startRendering:context` callback.
    TVIAudioDeviceContext deviceContext;

    // Maximum frames per buffer.
    size_t maxFramesPerBuffer;

    // Buffer passed to AVAudioEngine's manualRenderingBlock to receive the mixed audio data.
    AudioBufferList *bufferList;

    /*
     * Points to AVAudioEngine's manualRenderingBlock. This block is called from within the VoiceProcessingIO playout
     * callback in order to receive mixed audio data from AVAudioEngine in real time.
     */
    void *renderBlock;
} AudioRendererContext;

// Audio renderer contexts used in core audio's record callback to retrieve the sdk's audio device context.
typedef struct AudioCapturerContext {
    // Audio device context received in AudioDevice's `startCapturing:context` callback.
    TVIAudioDeviceContext deviceContext;

    // Preallocated buffer list. Please note the buffer itself will be provided by Core Audio's VoiceProcessingIO audio unit.
    AudioBufferList *bufferList;

    // Preallocated mixed (AudioUnit mic + AVAudioPlayerNode file) audio buffer list.
    AudioBufferList *mixedAudioBufferList;

    // Core Audio's VoiceProcessingIO audio unit.
    AudioUnit audioUnit;

    /*
     * Points to AVAudioEngine's manualRenderingBlock. This block is called from within the VoiceProcessingIO playout
     * callback in order to receive mixed audio data from AVAudioEngine in real time.
     */
    void *renderBlock;
} AudioCapturerContext;

// The VoiceProcessingIO audio unit uses bus 0 for ouptut, and bus 1 for input.
static int kOutputBus = 0;
static int kInputBus = 1;

static bool isStereo;

// This is the maximum slice size for VoiceProcessingIO (as observed in the field). We will double check at initialization time.
static size_t kMaximumFramesPerBuffer = 3072;

@interface RCTTWCustomAudioDevice()

@property (nonatomic, assign, getter=isInterrupted) BOOL interrupted;
@property (nonatomic, assign) AudioUnit audioUnit;
@property (nonatomic, assign) AudioBufferList captureBufferList;

@property (nonatomic, strong, nullable) TVIAudioFormat *renderingFormat;
@property (nonatomic, strong, nullable) TVIAudioFormat *capturingFormat;
@property (atomic, assign) AudioRendererContext *renderingContext;
@property (nonatomic, assign) AudioCapturerContext *capturingContext;

// AudioEngine properties
@property (nonatomic, strong) AVAudioEngine *playoutEngine;
@property (nonatomic, strong) AVAudioEngine *recordEngine;

@property (nonatomic, strong) AVAudioPlayerNode *tonePlayer;
@property (nonatomic, strong) AVAudioUnitTimePitch *tonePitchUnit;


@end

@implementation RCTTWCustomAudioDevice

#pragma mark - Init & Dealloc

- (id)init {
    self = [super init];

    if (self) {
        
        // Make sure stereo mode is disabled on start
        isStereo = false;
        
        /*
         * Initialize rendering and capturing context. The deviceContext will be be filled in when startRendering or
         * startCapturing gets called.
         */

        // Initialize the rendering context
        self.renderingContext = malloc(sizeof(AudioRendererContext));
        memset(self.renderingContext, 0, sizeof(AudioRendererContext));

        // Setup the AVAudioEngine along with the rendering context
        if (![self setupPlayoutAudioEngine]) {
            NSLog(@"Failed to setup AVAudioEngine");
        }

        // Initialize the capturing context
        self.capturingContext = malloc(sizeof(AudioCapturerContext));
        memset(self.capturingContext, 0, sizeof(AudioCapturerContext));
        self.capturingContext->bufferList = &_captureBufferList;
        
        // Setup the AVAudioEngine along with the rendering context
        if (![self setupRecordAudioEngine]) {
            NSLog(@"Failed to setup AVAudioEngine");
        }
        
        [self setupAVAudioSession];
    }

    return self;
}

- (void)dealloc {
    [self unregisterAVAudioSessionObservers];

    [self teardownAudioEngine];

    free(self.renderingContext);
    self.renderingContext = NULL;

    AudioBufferList *mixedAudioBufferList = self.capturingContext->mixedAudioBufferList;
    if (mixedAudioBufferList) {
        for (size_t i = 0; i < mixedAudioBufferList->mNumberBuffers; i++) {
            free(mixedAudioBufferList->mBuffers[i].mData);
        }
        free(mixedAudioBufferList);
    }
    free(self.capturingContext);
    self.capturingContext = NULL;
}

+ (NSString *)description {
    return @"AVAudioEngine Audio Mixing";
}

/*
 * Determine at runtime the maximum slice size used by VoiceProcessingIO. Setting the stream format and sample rate
 * doesn't appear to impact the maximum size so we prefer to read this value once at initialization time.
 */
+ (void)initialize {
    AudioComponentDescription audioUnitDescription = [self audioUnitDescription];
    AudioComponent audioComponent = AudioComponentFindNext(NULL, &audioUnitDescription);
    AudioUnit audioUnit;
    OSStatus status = AudioComponentInstanceNew(audioComponent, &audioUnit);
    if (status != 0) {
        NSLog(@"Could not find VoiceProcessingIO AudioComponent instance!");
        return;
    }

    UInt32 framesPerSlice = 0;
    UInt32 propertySize = sizeof(framesPerSlice);
    status = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global, kOutputBus,
                                  &framesPerSlice, &propertySize);
    if (status != 0) {
        NSLog(@"Could not read VoiceProcessingIO AudioComponent instance!");
        AudioComponentInstanceDispose(audioUnit);
        return;
    }

    NSLog(@"This device uses a maximum slice size of %d frames.", (unsigned int)framesPerSlice);
    kMaximumFramesPerBuffer = (size_t)framesPerSlice;
    AudioComponentInstanceDispose(audioUnit);
}

#pragma mark - Private (AVAudioEngine)

- (BOOL)setupAudioEngine {
    return [self setupPlayoutAudioEngine] && [self setupRecordAudioEngine];
}

- (AVAudioEngine*)setupGenericAudioEngine:(NSError*)error {
    /*
     * By default AVAudioEngine will render to/from the audio device, and automatically establish connections between
     * nodes, e.g. inputNode -> effectNode -> outputNode.
     */
    AVAudioEngine* engine = [AVAudioEngine new];

    // AVAudioEngine operates on the same format as the Core Audio output bus.
    const AudioStreamBasicDescription asbd = [[[self class] activeFormat] streamDescription];
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithStreamDescription:&asbd];

    // Switch to manual rendering mode
    [engine stop];
    BOOL success = [engine enableManualRenderingMode:AVAudioEngineManualRenderingModeRealtime
                                                      format:format
                                           maximumFrameCount:(uint32_t)kMaximumFramesPerBuffer
                                                       error:&error];
    if (!success) {
        NSLog(@"Failed to setup manual rendering mode, error = %@", error);
        return NULL;
    }

    /*
     * In manual rendering mode, AVAudioEngine won't receive audio from the microhpone. Instead, it will receive the
     * audio data from the Video SDK and mix it in MainMixerNode. Here we connect the input node to the main mixer node.
     * InputNode -> MainMixer -> OutputNode
     */
    [engine connect:engine.inputNode to:engine.mainMixerNode format:format];
    
    return engine;
}

- (BOOL)setupRecordAudioEngine {
    NSAssert(_recordEngine == nil, @"AVAudioEngine is already configured");

    NSError *error = nil;
    _recordEngine = [self setupGenericAudioEngine:error];
    if (error != nil || _playoutEngine == nil) {
        NSLog(@"Failed to create audio engine, error = %@", error);
    }

    // The manual rendering block (called in Core Audio's VoiceProcessingIO's playout callback at real time)
    self.capturingContext->renderBlock = (__bridge void *)(_recordEngine.manualRenderingBlock);

    
    if (![_recordEngine startAndReturnError:&error]) {
        NSLog(@"Failed to start AVAudioEngine, error = %@", error);
        return NO;
    }

    return YES;
}

- (BOOL)setupPlayoutAudioEngine {
    NSAssert(_playoutEngine == nil, @"AVAudioEngine is already configured");

    NSError *error = nil;
    _playoutEngine = [self setupGenericAudioEngine:error];
    if (error != nil || _playoutEngine == nil) {
        NSLog(@"Failed to create audio engine, error = %@", error);
    }

    const AudioStreamBasicDescription asbd = [[[self class] activeFormat] streamDescription];
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithStreamDescription:&asbd];

    // Create a tone player on this engine
    [self createTonePlayerOnPlayoutEngine];
    
    // Set the block to provide input data to engine
    AudioRendererContext *context = _renderingContext;
    AVAudioInputNode *inputNode = _playoutEngine.inputNode;
    BOOL success = [inputNode setManualRenderingInputPCMFormat:format
                                               inputBlock: ^const AudioBufferList * _Nullable(AVAudioFrameCount inNumberOfFrames) {
                                                   assert(inNumberOfFrames <= kMaximumFramesPerBuffer);

                                                   AudioBufferList *bufferList = context->bufferList;
                                                   int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
                                                   UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;

                                                   if (context->deviceContext) {
                                                       /*
                                                        * Pull decoded, mixed audio data from the media engine into the
                                                        * AudioUnit's AudioBufferList.
                                                        */
                                                       TVIAudioDeviceReadRenderData(context->deviceContext, audioBuffer, audioBufferSizeInBytes);
                                                    
                                                   } else {

                                                       /*
                                                        * Return silence when we do not have the playout device context. This is the
                                                        * case when the remote participant has not published an audio track yet.
                                                        * Since the audio graph and audio engine has been setup, we can still play
                                                        * the music file using AVAudioEngine.
                                                        */
                                                       memset(audioBuffer, 0, audioBufferSizeInBytes);
                                                   }

                                                   return bufferList;
                                               }];
    if (!success) {
        NSLog(@"Failed to set the manual rendering block");
        return NO;
    }

    // The manual rendering block (called in Core Audio's VoiceProcessingIO's playout callback at real time)
    self.renderingContext->renderBlock = (__bridge void *)(_playoutEngine.manualRenderingBlock);

    success = [_playoutEngine startAndReturnError:&error];
    if (!success) {
        NSLog(@"Failed to start AVAudioEngine, error = %@", error);
        return NO;
    }

    return YES;
}

- (void)teardownRecordAudioEngine {
    [_recordEngine stop];
    _recordEngine = nil;
}

- (void)teardownPlayoutAudioEngine {
    [_playoutEngine stop];
    _playoutEngine = nil;
}

- (void)teardownAudioEngine {
    [self teardownPlayoutFilePlayer];

    [self teardownPlayoutAudioEngine];
    [self teardownRecordAudioEngine];
}

- (void)makeStereo:(bool)stereo {
    isStereo = stereo;
    
    [self setupAVAudioSession];
    [self handleValidRouteChange];
}

- (bool)playBuffer:(AVAudioPCMBuffer*)buffer isLooping:(BOOL)isLooping volume:(float)volume playbackSpeed:(float)playbackSpeed {
    
    if (!self.playoutEngine) {
        NSLog(@"Trying to call playBuffer before playout engine is created!");
        return false;
    } else {
        if (self.playoutEngine.isRunning == false) {
            NSLog(@"Trying to call playBuffer before playout engine is running!");
            return false;
        }
    }

    if (!self.tonePlayer) {
        NSLog(@"Trying to call playBuffer before tonePlayer is created!");
        return false;
    }
    
    // Set play out options to make audio loopable
    AVAudioPlayerNodeBufferOptions options;
    if (isLooping) {
        options = AVAudioPlayerNodeBufferInterrupts|AVAudioPlayerNodeBufferLoops;
    } else {
        options = AVAudioPlayerNodeBufferInterrupts;
    }
    
    // Make sure volume is between 0 and 1.0f
    volume = MIN(MAX(volume, 0.0f), 1.0f);
    
    self.tonePitchUnit.rate = playbackSpeed;
    self.tonePlayer.volume = volume;
    
    // Schedule the provided music buffer to play on the playoutFilePlayer
    [self.tonePlayer scheduleBuffer:buffer
                                    atTime:nil
                                   options:options
                         completionHandler:nil];
    
    // Actually play the music on the node
    [self.tonePlayer play];
    
    return true;
}

- (void)pausePlayback {
    if (!self.tonePlayer) {
        NSLog(@"Trying to call pausePlayback before tonePlayer is created!");
        return;
    }
    
    [self.tonePlayer pause];
}

- (void)setPlaybackVolume:(float)volume {
    if (!self.tonePlayer) {
        NSLog(@"Trying to call setPlaybackVolume before tonePlayer is created!");
        return;
    }
    
    NSLog(@"Setting Volume %f", volume);
    [self.tonePlayer setVolume:volume];
}

- (void)setPlaybackSpeed:(float)playbackSpeed {
    if (!self.tonePitchUnit) {
        NSLog(@"Trying to call setPlaybackSpeed before tonePitchUnit is created!");
        return;
    }
    
    NSLog(@"Setting tonePitchUnit Rate %f", playbackSpeed);
    [self.tonePitchUnit setRate:playbackSpeed];
}

- (void)createTonePlayerOnPlayoutEngine {
    if (!self.playoutEngine) {
        NSLog(@"Cannot createTonePlayerOnPlayoutEngine. AudioEngine has not been created yet.");
        return;
    }

    // We create 3 audio unit nodes and connect them to the audio engine
    // Player -> EQ -> Time Pitch    
    self.tonePlayer = [[AVAudioPlayerNode alloc] init];
    self.tonePitchUnit = [[AVAudioUnitTimePitch alloc] init];
    
    [self.playoutEngine attachNode:self.tonePlayer];
    [self.playoutEngine attachNode:self.tonePitchUnit];
    
    [self.playoutEngine connect:self.tonePlayer to:self.tonePitchUnit format:nil];
    [self.playoutEngine connect:self.tonePitchUnit to:self.playoutEngine.mainMixerNode format:nil];
}

- (void)teardownPlayoutFilePlayer {
    if (self.tonePlayer) {
        if (self.tonePlayer.isPlaying) {
            [self.tonePlayer stop];
        }
        [self.playoutEngine detachNode:self.tonePlayer];
        [self.playoutEngine detachNode:self.tonePitchUnit];

        self.tonePlayer = nil;
        self.tonePitchUnit = nil;
    }
}

#pragma mark - TVIAudioDeviceRenderer

- (nullable TVIAudioFormat *)renderFormat {
    if (!_renderingFormat) {

        /*
         * Assume that the AVAudioSession has already been configured and started and that the values
         * for sampleRate and IOBufferDuration are final.
         */
        _renderingFormat = [[self class] activeFormat];
        self.renderingContext->maxFramesPerBuffer = _renderingFormat.framesPerBuffer;
    }

    return _renderingFormat;
}

- (BOOL)initializeRenderer {
    /*
     * In this example we don't need any fixed size buffers or other pre-allocated resources. We will simply write
     * directly to the AudioBufferList provided in the AudioUnit's rendering callback.
     */
    return YES;
}

- (BOOL)startRendering:(nonnull TVIAudioDeviceContext)context {
    @synchronized(self) {
        /*
         * In this example, the app always publishes an audio track. So we will start the audio unit from the capturer
         * call backs. We will restart the audio unit if a remote participant adds an audio track after the audio graph is
         * established. Also we will re-establish the audio graph in case the format changes.
         */
        if (_audioUnit) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }

        // We will make sure AVAudioEngine and AVAudioPlayerNode is accessed on the main queue.
        dispatch_async(dispatch_get_main_queue(), ^{
            AVAudioFormat *manualRenderingFormat  = self.playoutEngine.manualRenderingFormat;
            TVIAudioFormat *engineFormat = [[TVIAudioFormat alloc] initWithChannels:manualRenderingFormat.channelCount
                                                                         sampleRate:manualRenderingFormat.sampleRate
                                                                    framesPerBuffer:kMaximumFramesPerBuffer];
            if ([engineFormat isEqual:[[self class] activeFormat]]) {
                if (self.playoutEngine.isRunning) {
                    [self.playoutEngine stop];
                }
                
                NSError *error = nil;
                if (![self.playoutEngine startAndReturnError:&error]) {
                    NSLog(@"Failed to start AVAudioEngine, error = %@", error);
                }
            } else {
                [self teardownPlayoutFilePlayer];
                [self teardownPlayoutAudioEngine];
                [self setupPlayoutAudioEngine];
            }
        });

        self.renderingContext->deviceContext = context;

        if (![self setupAudioUnitWithRenderContext:self.renderingContext
                                    captureContext:self.capturingContext]) {
            return NO;
        }
        BOOL success = [self startAudioUnit];
        return success;
    }
}

- (BOOL)stopRendering {
    @synchronized(self) {
        // If the capturer is runnning, we will not stop the audio unit.
        if (!self.capturingContext->deviceContext) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }
        self.renderingContext->deviceContext = NULL;
        
        // We will make sure AVAudioEngine and AVAudioPlayerNode is accessed on the main queue.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.playoutEngine.isRunning) {
                [self.playoutEngine stop];
            }
        });
    }

    return YES;
}

#pragma mark - TVIAudioDeviceCapturer

- (nullable TVIAudioFormat *)captureFormat {
    if (!_capturingFormat) {

        /*
         * Assume that the AVAudioSession has already been configured and started and that the values
         * for sampleRate and IOBufferDuration are final.
         */
        _capturingFormat = [[self class] activeFormat];
    }

    return _capturingFormat;
}

- (BOOL)initializeCapturer {
    _captureBufferList.mNumberBuffers = 1;
    _captureBufferList.mBuffers[0].mNumberChannels = kPreferredNumberOfChannels;

    AudioBufferList *mixedAudioBufferList = self.capturingContext->mixedAudioBufferList;
    if (mixedAudioBufferList == NULL) {
        mixedAudioBufferList = (AudioBufferList*)malloc(sizeof(AudioBufferList));
        mixedAudioBufferList->mNumberBuffers = 1;
        mixedAudioBufferList->mBuffers[0].mNumberChannels = kPreferredNumberOfChannels;
        mixedAudioBufferList->mBuffers[0].mDataByteSize = 0;
        mixedAudioBufferList->mBuffers[0].mData = malloc(kMaximumFramesPerBuffer * kPreferredNumberOfChannels * kAudioSampleSize);

        self.capturingContext->mixedAudioBufferList = mixedAudioBufferList;
    }

    return YES;
}

- (BOOL)startCapturing:(nonnull TVIAudioDeviceContext)context {
    @synchronized (self) {

        // Restart the audio unit if the audio graph is alreay setup and if we publish an audio track.
        if (_audioUnit) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }

        // We will make sure AVAudioEngine and AVAudioPlayerNode is accessed on the main queue.
        dispatch_async(dispatch_get_main_queue(), ^{
            AVAudioFormat *manualRenderingFormat  = self.recordEngine.manualRenderingFormat;
            TVIAudioFormat *engineFormat = [[TVIAudioFormat alloc] initWithChannels:manualRenderingFormat.channelCount
                                                                         sampleRate:manualRenderingFormat.sampleRate
                                                                    framesPerBuffer:kMaximumFramesPerBuffer];
            if ([engineFormat isEqual:[[self class] activeFormat]]) {
                if (self.recordEngine.isRunning) {
                    [self.recordEngine stop];
                }
                
                NSError *error = nil;
                if (![self.recordEngine startAndReturnError:&error]) {
                    NSLog(@"Failed to start AVAudioEngine, error = %@", error);
                }
            } else {
                [self teardownRecordAudioEngine];
                [self setupRecordAudioEngine];
            }
        });

        self.capturingContext->deviceContext = context;

        if (![self setupAudioUnitWithRenderContext:self.renderingContext
                                    captureContext:self.capturingContext]) {
            return NO;
        }

        BOOL success = [self startAudioUnit];
        return success;
    }
}

- (BOOL)stopCapturing {
    @synchronized(self) {
        // If the renderer is runnning, we will not stop the audio unit.
        if (!self.renderingContext->deviceContext) {
            [self stopAudioUnit];
            [self teardownAudioUnit];
        }
        self.capturingContext->deviceContext = NULL;
        
        // We will make sure AVAudioEngine and AVAudioPlayerNode is accessed on the main queue.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.recordEngine.isRunning) {
                [self.recordEngine stop];
            }
        });
    }

    return YES;
}

#pragma mark - Private (AudioUnit callbacks)

static OSStatus CustomAudioDevicePlayoutCallback(void *refCon,
                                                          AudioUnitRenderActionFlags *actionFlags,
                                                          const AudioTimeStamp *timestamp,
                                                          UInt32 busNumber,
                                                          UInt32 numFrames,
                                                          AudioBufferList *bufferList) NS_AVAILABLE(NA, 11_0) {
    assert(bufferList->mNumberBuffers == 1);
    assert(bufferList->mBuffers[0].mNumberChannels <= 2);
    assert(bufferList->mBuffers[0].mNumberChannels > 0);

    AudioRendererContext *context = (AudioRendererContext *)refCon;
    context->bufferList = bufferList;

    int8_t *audioBuffer = (int8_t *)bufferList->mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = bufferList->mBuffers[0].mDataByteSize;

    // Pull decoded, mixed audio data from the media engine into the AudioUnit's AudioBufferList.
    assert(audioBufferSizeInBytes == (bufferList->mBuffers[0].mNumberChannels * kAudioSampleSize * numFrames));
    OSStatus outputStatus = noErr;

    // Get the mixed audio data from AVAudioEngine's output node by calling the `renderBlock`
    AVAudioEngineManualRenderingBlock renderBlock = (__bridge AVAudioEngineManualRenderingBlock)(context->renderBlock);
    const AVAudioEngineManualRenderingStatus status = renderBlock(numFrames, bufferList, &outputStatus);

    /*
     * Render silence if there are temporary mismatches between CoreAudio and our rendering format or AVAudioEngine
     * could not render the audio samples.
     */
    if (numFrames > context->maxFramesPerBuffer || status != AVAudioEngineManualRenderingStatusSuccess) {
        if (numFrames > context->maxFramesPerBuffer) {
            NSLog(@"Can handle a max of %u frames but got %u.", (unsigned int)context->maxFramesPerBuffer, (unsigned int)numFrames);
        }
        *actionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        memset(audioBuffer, 0, audioBufferSizeInBytes);
    }

    return noErr;
}

static OSStatus CustomAudioDeviceRecordCallback(void *refCon,
                                                         AudioUnitRenderActionFlags *actionFlags,
                                                         const AudioTimeStamp *timestamp,
                                                         UInt32 busNumber,
                                                         UInt32 numFrames,
                                                         AudioBufferList *bufferList) NS_AVAILABLE(NA, 11_0) {

    if (numFrames > kMaximumFramesPerBuffer) {
        NSLog(@"Expected %u frames but got %u.", (unsigned int)kMaximumFramesPerBuffer, (unsigned int)numFrames);
        return noErr;
    }

    AudioCapturerContext *context = (AudioCapturerContext *)refCon;

    if (context->deviceContext == NULL) {
        return noErr;
    }

    AudioBufferList *audioBufferList = context->bufferList;
    audioBufferList->mBuffers[0].mDataByteSize = numFrames * sizeof(UInt16) * kPreferredNumberOfChannels;
    // The buffer will be filled by VoiceProcessingIO AudioUnit
    audioBufferList->mBuffers[0].mData = NULL;

    OSStatus status = noErr;
    status = AudioUnitRender(context->audioUnit,
                             actionFlags,
                             timestamp,
                             1,
                             numFrames,
                             audioBufferList);

    AudioBufferList *mixedAudioBufferList = context->mixedAudioBufferList;
    assert(mixedAudioBufferList != NULL);
    assert(mixedAudioBufferList->mNumberBuffers == audioBufferList->mNumberBuffers);
    for(int i = 0; i < audioBufferList->mNumberBuffers; i++) {
        mixedAudioBufferList->mBuffers[i].mNumberChannels = audioBufferList->mBuffers[i].mNumberChannels;
        mixedAudioBufferList->mBuffers[i].mDataByteSize = audioBufferList->mBuffers[i].mDataByteSize;
    }

    OSStatus outputStatus = noErr;
    AVAudioEngineManualRenderingBlock renderBlock = (__bridge AVAudioEngineManualRenderingBlock)(context->renderBlock);
    const AVAudioEngineManualRenderingStatus ret = renderBlock(numFrames, mixedAudioBufferList, &outputStatus);

    if (ret != AVAudioEngineManualRenderingStatusSuccess) {
        NSLog(@"AVAudioEngine failed mix audio");
    }

    int8_t *audioBuffer = (int8_t *)mixedAudioBufferList->mBuffers[0].mData;
    UInt32 audioBufferSizeInBytes = mixedAudioBufferList->mBuffers[0].mDataByteSize;

    if (context->deviceContext && audioBuffer) {
        TVIAudioDeviceWriteCaptureData(context->deviceContext, audioBuffer, audioBufferSizeInBytes);
    }

    return noErr;
}

#pragma mark - Private (AVAudioSession and CoreAudio)

+ (nullable TVIAudioFormat *)activeFormat {
    /*
     * Use the pre-determined maximum frame size. AudioUnit callbacks are variable, and in most sitations will be close
     * to the `AVAudioSession.preferredIOBufferDuration` that we've requested.
     */
    const size_t sessionFramesPerBuffer = kMaximumFramesPerBuffer;
    const double sessionSampleRate = [AVAudioSession sharedInstance].sampleRate;

    if (isStereo) {
        return [[TVIAudioFormat alloc] initWithChannels:TVIAudioChannelsStereo
                                         sampleRate:sessionSampleRate
                                    framesPerBuffer:sessionFramesPerBuffer];
    } else {
        return [[TVIAudioFormat alloc] initWithChannels:TVIAudioChannelsMono
             sampleRate:sessionSampleRate
        framesPerBuffer:sessionFramesPerBuffer];
    }
}

+ (AudioComponentDescription)audioUnitDescription {
    AudioComponentDescription audioUnitDescription;
    audioUnitDescription.componentType = kAudioUnitType_Output;
    if (isStereo) {
        audioUnitDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    } else {
        audioUnitDescription.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    }
    audioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioUnitDescription.componentFlags = 0;
    audioUnitDescription.componentFlagsMask = 0;
    return audioUnitDescription;
}

- (void)setupAVAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    /*
     * We want to be as close as possible to the 10 millisecond buffer size that the media engine needs. If there is
     * a mismatch then TwilioVideo will ensure that appropriately sized audio buffers are delivered.
     */
    if (![session setPreferredIOBufferDuration:kPreferredIOBufferDuration error:&error]) {
        NSLog(@"Error setting IOBuffer duration: %@", error);
    }

    if (isStereo) {
        if (![session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetoothA2DP error:&error]) {
            NSLog(@"Error setting session category: %@", error);
        }
    } else {
        if (![session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetoothA2DP|AVAudioSessionCategoryOptionAllowBluetooth error:&error]) {
            NSLog(@"Error setting session category: %@", error);
        }
    }
//
    if (![session setMode:AVAudioSessionModeVideoChat error:&error]) {
        NSLog(@"Error setting session category: %@", error);
    }
    
    if (![session setPreferredSampleRate:kPreferredSampleRate error:&error]) {
        NSLog(@"Error setting sample rate: %@", error);
    }

    if (isStereo) {
        if (![session setPreferredOutputNumberOfChannels:2 error:&error]) {
            NSLog(@"Error setting number of output channels: %@", error);
        }
    } else {
        if (![session setPreferredOutputNumberOfChannels:1 error:&error]) {
            NSLog(@"Error setting number of output channels: %@", error);
        }
    }
    

    [self registerAVAudioSessionObservers];
}

- (BOOL)setupAudioUnitWithRenderContext:(AudioRendererContext *)renderContext
                         captureContext:(AudioCapturerContext *)captureContext {

    // Find and instantiate the VoiceProcessingIO audio unit.
    AudioComponentDescription audioUnitDescription = [[self class] audioUnitDescription];
    AudioComponent audioComponent = AudioComponentFindNext(NULL, &audioUnitDescription);

    OSStatus status = AudioComponentInstanceNew(audioComponent, &_audioUnit);
    if (status != 0) {
        NSLog(@"Could not find VoiceProcessingIO AudioComponent instance!");
        return NO;
    }

    /*
     * Configure the VoiceProcessingIO audio unit. Our rendering format attempts to match what AVAudioSession requires
     * to prevent any additional format conversions after the media engine has mixed our playout audio.
     */
    AudioStreamBasicDescription streamDescription = self.renderingFormat.streamDescription;

    UInt32 enableOutput = 1;
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output, kOutputBus,
                                  &enableOutput, sizeof(enableOutput));
    if (status != 0) {
        NSLog(@"Could not enable out bus!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output, kInputBus,
                                  &streamDescription, sizeof(streamDescription));
    if (status != 0) {
        NSLog(@"Could not set stream format on input bus!");
        return NO;
    }

    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input, kOutputBus,
                                  &streamDescription, sizeof(streamDescription));
    if (status != 0) {
        NSLog(@"Could not set stream format on output bus!");
        return NO;
    }

    // Enable the microphone input
    UInt32 enableInput = 1;
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input, kInputBus, &enableInput,
                                  sizeof(enableInput));

    if (status != 0) {
        NSLog(@"Could not enable input bus!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    // Setup the rendering callback.
    AURenderCallbackStruct renderCallback;
    renderCallback.inputProc = CustomAudioDevicePlayoutCallback;
    renderCallback.inputProcRefCon = (void *)(renderContext);
    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Output, kOutputBus, &renderCallback,
                                  sizeof(renderCallback));
    if (status != 0) {
        NSLog(@"Could not set rendering callback!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    // Setup the capturing callback.
    AURenderCallbackStruct captureCallback;
    captureCallback.inputProc = CustomAudioDeviceRecordCallback;
    captureCallback.inputProcRefCon = (void *)(captureContext);
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Input, kInputBus, &captureCallback,
                                  sizeof(captureCallback));
    if (status != 0) {
        NSLog(@"Could not set capturing callback!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    // Try to initalize the Audio Unit a max of kMaxNumberOfAudioUnitInitializeAttempts
    NSInteger failedInitializeAttempts = 0;
    while (status != noErr) {
        NSLog(@"Failed to initialize the Voice Processing I/O unit. Error= %ld.", (long)status);
        ++failedInitializeAttempts;
        if (failedInitializeAttempts == kMaxNumberOfAudioUnitInitializeAttempts) {
            break;
        }
        NSLog(@"Pause 100ms and try audio unit initialization again.");
        [NSThread sleepForTimeInterval:0.1f];
        
        // Finally, initialize and start the audio unit.
        status = AudioUnitInitialize(_audioUnit);
    }

    // If we still weren't able to initialize the AudioUnit, return failure
    if (status != 0) {
        NSLog(@"Could not initialize the audio unit!");
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
        return NO;
    }

    captureContext->audioUnit = _audioUnit;

    return YES;
}

- (BOOL)startAudioUnit {
    OSStatus status = AudioOutputUnitStart(_audioUnit);
    if (status != 0) {
        NSLog(@"Could not start the audio unit!");
        return NO;
    }
    return YES;
}

- (BOOL)stopAudioUnit {
    OSStatus status = AudioOutputUnitStop(_audioUnit);
    if (status != 0) {
        NSLog(@"Could not stop the audio unit!");
        return NO;
    }
    return YES;
}

- (void)teardownAudioUnit {
    if (_audioUnit) {
        AudioUnitUninitialize(_audioUnit);
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
    }
}

#pragma mark - NSNotification Observers

- (TVIAudioDeviceContext)deviceContext {
    if (self.renderingContext->deviceContext) {
        return self.renderingContext->deviceContext;
    } else if (self.capturingContext->deviceContext) {
        return self.capturingContext->deviceContext;
    }
    return NULL;
}

- (void)registerAVAudioSessionObservers {
    // An audio device that interacts with AVAudioSession should handle events like interruptions and route changes.
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserver:self selector:@selector(handleAudioInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
    [center addObserver:self selector:@selector(handleApplicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(handleRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];
    [center addObserver:self selector:@selector(handleMediaServiceLost:) name:AVAudioSessionMediaServicesWereLostNotification object:nil];
    [center addObserver:self selector:@selector(handleMediaServiceRestored:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];
}

- (void)handleAudioInterruption:(NSNotification *)notification {
    AVAudioSessionInterruptionType type = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];

    @synchronized(self) {
        // If the worker block is executed, then context is guaranteed to be valid.
        TVIAudioDeviceContext context = [self deviceContext];
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
                if (type == AVAudioSessionInterruptionTypeBegan) {
                    NSLog(@"Interruption began.");
                    self.interrupted = YES;
                    [self stopAudioUnit];
                } else {
                    NSLog(@"Interruption ended.");
                    self.interrupted = NO;
                    [self startAudioUnit];
                }
            });
        }
    }
}

- (void)handleApplicationDidBecomeActive:(NSNotification *)notification {
    @synchronized(self) {
        // If the worker block is executed, then context is guaranteed to be valid.
        TVIAudioDeviceContext context = [self deviceContext];
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
                if (self.isInterrupted) {
                    NSLog(@"Synthesizing an interruption ended event for iOS 9.x devices.");
                    self.interrupted = NO;
                    [self startAudioUnit];
                }
            });
        }
    }
}

- (void)handleRouteChange:(NSNotification *)notification {
    // Check if the sample rate, or channels changed and trigger a format change if it did.
    AVAudioSessionRouteChangeReason reason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];

    switch (reason) {
        case AVAudioSessionRouteChangeReasonUnknown:
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            // Each device change might cause the actual sample rate or channel configuration of the session to change.
        case AVAudioSessionRouteChangeReasonCategoryChange:
            // In iOS 9.2+ switching routes from a BT device in control center may cause a category change.
        case AVAudioSessionRouteChangeReasonOverride:
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
        case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
            // With CallKit, AVAudioSession may change the sample rate during a configuration change.
            // If a valid route change occurs we may want to update our audio graph to reflect the new output device.
            @synchronized(self) {
                // If the worker block is executed, then context is guaranteed to be valid.
                TVIAudioDeviceContext context = [self deviceContext];
                if (context) {
                    TVIAudioDeviceExecuteWorkerBlock(context, ^{
                        [self handleValidRouteChange];
                    });
                }
            }
            break;
    }
}

- (void)handleValidRouteChange {
    // Nothing to process while we are interrupted. We will interrogate the AVAudioSession once the interruption ends.
    if (self.isInterrupted) {
        return;
    } else if (_audioUnit == NULL) {
        return;
    }

    NSLog(@"A route change ocurred while the AudioUnit was started. Checking the active audio format.");

    // Determine if the format actually changed. We only care about sample rate and number of channels.
    TVIAudioFormat *activeFormat = [[self class] activeFormat];

    // Notify Video SDK about the format change
    if (![activeFormat isEqual:_renderingFormat] ||
        ![activeFormat isEqual:_capturingFormat]) {

        NSLog(@"Format changed, restarting with %@", activeFormat);

        // Signal a change by clearing our cached format, and allowing TVIAudioDevice to drive the process.
        _renderingFormat = nil;
        _capturingFormat = nil;

        @synchronized(self) {
            TVIAudioDeviceContext context = [self deviceContext];
            if (context) {
                TVIAudioDeviceFormatChanged(context);
            }
        }
    }
}

- (void)handleMediaServiceLost:(NSNotification *)notification {
    [self teardownAudioEngine];

    @synchronized(self) {
        // If the worker block is executed, then context is guaranteed to be valid.
        TVIAudioDeviceContext context = [self deviceContext];
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
                [self teardownAudioUnit];
            });
        }
    }
}

- (void)handleMediaServiceRestored:(NSNotification *)notification {
    [self setupAudioEngine];

    @synchronized(self) {
        // If the worker block is executed, then context is guaranteed to be valid.
        TVIAudioDeviceContext context = [self deviceContext];
        if (context) {
            TVIAudioDeviceExecuteWorkerBlock(context, ^{
                [self startAudioUnit];
            });
        }
    }
}

- (void)unregisterAVAudioSessionObservers {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
