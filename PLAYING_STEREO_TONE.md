

# Playing Stereo Tones during a Call

This repo contains a major change from the upstream branch which allows playing stereo tones during a call. This is a feature request for our product NiceDay.

This document explains an overview of the problem and changes required in the wrapper to achieve this.

## How to use

Checkout the [example](https://github.com/senseobservationsystems/react-native-twilio-video-webrtc/tree/niceday/twilio-emdr-ready/Example) to see how to play stereo tones during a call

To enable stereo audio during a call, call the method `setStereoEnabled(true)` which would cause all audio from then onwards to be stereo.

You are free to disable stereo during a call as well by passing `false` to the same function.

To play an audio to be Stereo using the `TwilioStereoTonePlayer`. 

`TwilioStereoTonePlayer` is initialised by default to keep a maximum of 5 files in memory (i.e you can have a maximum of 5 files in memory), you are free to modify this number [here](https://github.com/senseobservationsystems/react-native-twilio-video-webrtc/blob/niceday/twilio-emdr-ready/src/TwilioStereoTonePlayer.js#L16) but beware that this will cause high memory usage.

Every time you call `preload` or `play` for a file that you have not played previously, the file is loaded to memory and not released unless you call `release` or `terminate`.

Note: If you call `terminate` you have to create a new `TwilioStereoTonePlayer` object to use the tone player.

The `TwilioStereoTonePlayer` only plays 1 file at a time and if there is any other sound playing it is first paused before the new sound is played.

### Known issues playing stereo sounds during a call

Fundamentally all calls on Android (> Android 8) and iOS default to mono. 

This comes from fundamental restrictions coming from how the voice processing units works in iOS and how android changes the internal audio system when we give a hint to optimise all OS audio for an ongoing VOIP call.

You can see the original issues in Twilio repo for [iOS](https://github.com/twilio/twilio-video-ios/issues/77) and [Android](https://github.com/twilio/video-quickstart-android/issues/533)

## Playing stereo sounds during a call

### Android

In Android when starting a VOIP call we [request audio focus](https://developer.android.com/guide/topics/media-apps/audio-focus) from the operating system. This is basically telling the OS that we are going to be using the audio engine for a special reason (i.e VOIP call) and to make sure the OS can mute all other music being played. This will either stop your ongoing spotify song or will `duck` (i.e reduce the volume of your ongoing spotty song to be very low).

Managing audio focus is a recommended approach for playing nice with other applications running on the OS.

I have explained what goes wrong with audio focus making the sound to become  mono in this comment: https://github.com/twilio/video-quickstart-android/issues/533#issuecomment-647399857

### iOS

In iOS when starting a VOIP call using Twilio, we initialise the WebRTC audio engine internally.

WebRTC, uses the recommended approach of trying to play audio from the lowest latency and highest quality possible which is by using something [audio unit](https://developer.apple.com/documentation/audiounit) and more specifically routes all audio through an audio unit called the [Voice Processing audio unit](https://developer.apple.com/documentation/avfoundation/audio_playback_recording_and_processing/avaudioengine/using_voice_processing).

This is a hardware audio unit that adds features like echo cancellation, automatic gain, etc.

The problem with the voice processing audio unit is that its monophonic by default. Which means all audio passing though this audio unit will always be mono.

To solve this, we use Twilio with a custom audio device and set the audio unit mode to be generic instead of voice processing unit which allows all sound flowing through it to be stereo. 

An example of using a custom device with Twilio is available in the Twilio [Examples](https://github.com/twilio/video-quickstart-ios/tree/master/AudioDeviceExample) and there is a draft PR to see the changes required to make a custom audio device that is stereo ready [here] (https://github.com/umarniz/video-quickstart-ios/pull/1/files)

## FAQ

- Do I need to play sounds using the `TwilioStereoTonePlayer` for sound to be stereo?

Once you call `setStereoEnabled(true)` on Android every sound you play (including external audio players) will be stereo

On iOS, you can only play stereo sounds from the StereoTonePlayer.

- Does this PR change the way audio is processed compared to the upstream master?

Yes, for IOS we need to create a custom audio device which fundamentally changes the way audio is processed.

- HELP, I am seeing native crashes in production if we do normal Twilio calls with this repo!

There is an [emergency kill switch](https://github.com/senseobservationsystems/react-native-twilio-video-webrtc/blob/niceday/twilio-emdr-ready/src/TwilioVideo.ios.js#L162) in TwilioVideo.ios.js with the property `this.usesCustomAudioDevice = true;` 

If you set this constant to `false`  and don't call `setStereoEnabled(true)` then this repo should function exactly the same as without having any of the code required for stereo calls.