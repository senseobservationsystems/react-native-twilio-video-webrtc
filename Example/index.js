import React, { Component } from 'react';
import {
  AppRegistry,
  StyleSheet,
  Text,
  TextInput,
  View,
  Button,
  PermissionsAndroid,
  Platform,
  TouchableOpacity,
  Dimensions
} from 'react-native';

import {
  TwilioStereoTonePlayer,
  TwilioVideoLocalView,
  TwilioVideoParticipantView,
  TwilioVideo
} from 'react-native-twilio-video-webrtc'

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: 'white'
  },
  callContainer: {
    flex: 1,
    position: "absolute",
    bottom: 0,
    top: 0,
    left: 0,
    right: 0
  },
  welcome: {
    fontSize: 30,
    textAlign: 'center',
    paddingTop: 40
  },
  input: {
    height: 50,
    borderWidth: 1,
    marginRight: 70,
    marginLeft: 70,
    marginTop: 50,
    textAlign: 'center',
    backgroundColor: 'white'
  },
  button: {
    marginTop: 100
  },
  localVideo: {
    flex: 1,
    width: 150,
    height: 250,
    position: "absolute",
    right: 10,
    bottom: 10
  },
  remoteGrid: {
    flex: 1,
    flexDirection: "row",
    flexWrap: 'wrap'
  },
  remoteVideo: {
    marginTop: 20,
    marginLeft: 10,
    marginRight: 10,
    width: 100,
    height: 120,
  },
  optionsContainer: {
    position: "absolute",
    left: 0,
    bottom: 0,
    right: 0,
    height: 100,
    backgroundColor: 'blue',
    flexDirection: "row",
    alignItems: "center"
  },
  optionButton: {
    width: 60,
    height: 60,
    marginLeft: 10,
    marginRight: 10,
    borderRadius: 100 / 2,
    backgroundColor: 'grey',
    justifyContent: 'center',
    alignItems: "center"
  },
  playbackContainer: {
    position: "absolute",
    left: 0,
    bottom: 100,
    right: 0,
    height: 100,
    backgroundColor: 'blue',
    flexDirection: "row",
    alignItems: "center"
  },
  playbackButton: {
    width: 60,
    height: 60,
    marginLeft: 10,
    marginRight: 10,
    borderRadius: 100 / 2,
    backgroundColor: 'grey',
    justifyContent: 'center',
    alignItems: "center"
  }
});

export default class Example extends Component {
  state = {
    isAudioEnabled: true,
    isVideoEnabled: true,
    isStereoMode: false,
    isPlaying: false,
    playbackSpeed: 1.0,
    connectAttempt: 1,
    status: 'disconnected',
    mountStatus: 'unmounted',
    participants: new Map(),
    videoTracks: new Map(),
    token: '',
    iosToken: ''
  }
  
  _onConnectButtonPress = async () => {
    if (this.state.mountStatus == 'unmounted') {
      this.setState({mountStatus: 'mounted'})
      return;
    }

    if (Platform.OS === 'android') {
      await this._requestAudioPermission()
      await this._requestCameraPermission()
      this.refs.twilioVideo.connect({ accessToken: this.state.token, roomName: 'test', enableVideo: true  })
    } else {
      this.refs.twilioVideo.connect({ accessToken: this.state.iosToken, roomName: 'test', enableVideo: true })
    }

    this.audioPlayer = new TwilioStereoTonePlayer();
    this.setState({status: 'connecting', connectAttempt: this.state.connectAttempt+1})
  }

  _onEndButtonPress = () => {
    this.refs.twilioVideo.disconnect()
    this.audioPlayer.terminate()
  }

  _onMuteButtonPress = () => {
    this.refs.twilioVideo.setLocalAudioEnabled(!this.state.isAudioEnabled)
      .then(isEnabled => this.setState({isAudioEnabled: isEnabled}))
  }

  _onFlipButtonPress = () => {
    this.refs.twilioVideo.flipCamera()
  }

  _onStereoButtonPress = () => {
    this.refs.twilioVideo.setStereoEnabled(!this.state.isStereoMode)
      .then(isEnabled => this.setState({isStereoMode: isEnabled}))

    this.audioPlayer.pause();
    this.setState({isPlaying: false})
  }

  _onPlayTrackButtonPress = () => {
    if (!this.state.isPlaying) {
      this.audioPlayer.play("stereo_tone.wav", true, 0.5, 1.0);
      this.setState({isPlaying: true})
    } else {
      this.audioPlayer.pause();
      this.setState({isPlaying: false})
      this.setState({playbackSpeed: 1.0})
    }
  }

  _onChangePlaybackSpeedPress = () => {
    if (this.state.playbackSpeed < 2.0) {
      this.setState({playbackSpeed: 2.0})
    } else {
      this.setState({playbackSpeed: 1.0})
    }

    this.audioPlayer.setPlaybackSpeed(this.state.playbackSpeed);
  }

  _onRoomDidConnect = () => {
    this.setState({status: 'connected'})
  }

  _onRoomDidDisconnect = ({error}) => {
    console.log("ERROR: ", error)

    this.setState({status: 'disconnected'})

    this.setState({mountStatus: 'unmounted'})
  }

  _onRoomDidFailToConnect = (error) => {
    console.log("ERROR: ", error)

    this.setState({status: 'disconnected'})
  }

  _onParticipantAddedVideoTrack = ({participant, track}) => {
    console.log("onParticipantAddedVideoTrack: ", participant, track)

    this.setState({
      videoTracks: new Map([
        ...this.state.videoTracks,
        [track.trackSid, { participantSid: participant.sid, videoTrackSid: track.trackSid }]
      ]),
    });
  }

  _onParticipantRemovedVideoTrack = ({participant, track}) => {
    console.log("onParticipantRemovedVideoTrack: ", participant, track)

    const videoTracks = new Map(this.state.videoTracks);
    videoTracks.delete(track.trackSid)

    this.setState({ videoTracks });
  }

  _requestAudioPermission =  () => {
    return PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
      {
        title: "Need permission to access microphone",
        message:
          "To run this demo we need permission to access your microphone",
        buttonNegative: "Cancel",
        buttonPositive: "OK"
      }
    );
  }

  _requestCameraPermission =  () => {
    return PermissionsAndroid.request(
     PermissionsAndroid.PERMISSIONS.CAMERA,
      {
        title: "Need permission to access camera",
        message:
          "To run this demo we need permission to access your camera",
        buttonNegative: "Cancel",
        buttonPositive: "OK"
      }
    );
  }

  render() {
    return (
      <View style={styles.container}>
        {
          this.state.status === 'disconnected' &&
          <View>
            <Text style={styles.welcome}>
              React Native Twilio Video
            </Text>
            <TextInput
              style={styles.input}
              autoCapitalize='none'
              value={Platform.OS === 'android' ? this.state.token : this.state.iosToken}
              onChangeText={(text) => this.setState({token: text})}>
            </TextInput>
            <Button
              title={this.state.mountStatus != "mounted" ? "Mount Component" : "Connect"}
              style={styles.button}
              onPress={this._onConnectButtonPress}>
            </Button>
          </View>
        }

        {
          (this.state.status === 'connected' || this.state.status === 'connecting') &&
            <View style={styles.callContainer}>
            {
              this.state.status === 'connected' &&
              <View style={styles.remoteGrid}>
                {
                  Array.from(this.state.videoTracks, ([trackSid, trackIdentifier]) => {
                    return (
                      <TwilioVideoParticipantView
                        style={styles.remoteVideo}
                        key={trackSid}
                        trackIdentifier={trackIdentifier}
                      />
                    )
                  })
                }
              </View>
            }
            <View
              style={styles.playbackContainer}>
              <TouchableOpacity
                style={styles.optionButton}
                onPress={this._onStereoButtonPress}>
                <Text style={{fontSize: 12}}>{ this.state.isStereoMode ? "Make Mono" : "Make Stereo" }</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.optionButton}
                onPress={this._onPlayTrackButtonPress}>
                <Text style={{fontSize: 12}}>{ this.state.isPlaying ? "Pause" : "Play" }</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.optionButton}
                onPress={this._onChangePlaybackSpeedPress}>
                <Text style={{fontSize: 12}}>{"Play at " + this.state.playbackSpeed + "x"}</Text>
              </TouchableOpacity>
            </View>
            <View
              style={styles.optionsContainer}>
              <TouchableOpacity
                style={styles.optionButton}
                onPress={this._onEndButtonPress}>
                <Text style={{fontSize: 12}}>End</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.optionButton}
                onPress={this._onMuteButtonPress}>
                <Text style={{fontSize: 12}}>{ this.state.isAudioEnabled ? "Mute" : "Unmute" }</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.optionButton}
                onPress={this._onFlipButtonPress}>
                <Text style={{fontSize: 12}}>Flip</Text>
              </TouchableOpacity>
              <TwilioVideoLocalView
                enabled={true}
                style={styles.localVideo}
              />
            </View>
          </View>
        }

        {
          this.state.mountStatus === 'mounted' &&
          <TwilioVideo
            ref="twilioVideo"
            onRoomDidConnect={ this._onRoomDidConnect }
            onRoomDidDisconnect={ this._onRoomDidDisconnect }
            onRoomDidFailToConnect= { this._onRoomDidFailToConnect }
            onParticipantAddedVideoTrack={ this._onParticipantAddedVideoTrack }
            onParticipantRemovedVideoTrack= { this._onParticipantRemovedVideoTrack }
          />
        }
      </View>
    );
  }
}

AppRegistry.registerComponent('Example', () => Example);
