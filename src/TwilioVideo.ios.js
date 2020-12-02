//
//  TwilioVideo.js
//  Black
//
//  Created by Martín Fernández on 6/13/17.
//
//

import { Component } from 'react'
import PropTypes from 'prop-types'
import { NativeModules, NativeEventEmitter, View } from 'react-native'

const { TWVideoModule } = NativeModules

export default class extends Component {
  static propTypes = {
    /**
     * Flag that enables screen sharing RCTRootView instead of camera capture
     */
    screenShare: PropTypes.bool,
    /**
     * Called when the room has connected
     *
     * @param {{roomName, participants}}
     */
    onRoomDidConnect: PropTypes.func,
    /**
     * Called when the room has disconnected
     *
     * @param {{roomName, error}}
     */
    onRoomDidDisconnect: PropTypes.func,
    /**
     * Called when connection with room failed
     *
     * @param {{roomName, error}}
     */
    onRoomDidFailToConnect: PropTypes.func,
    /**
     * Called when a new participant has connected
     *
     * @param {{roomName, participant}}
     */
    onRoomParticipantDidConnect: PropTypes.func,
    /**
     * Called when a participant has disconnected
     *
     * @param {{roomName, participant}}
     */
    onRoomParticipantDidDisconnect: PropTypes.func,
    /**
     * Called when a new video track has been added
     *
     * @param {{participant, track, enabled}}
     */
    onParticipantAddedVideoTrack: PropTypes.func,
    /**
     * Called when a video track has been removed
     *
     * @param {{participant, track}}
     */
    onParticipantRemovedVideoTrack: PropTypes.func,
    /**
     * Called when a new data track has been added
     *
     * @param {{participant, track}}
     */
    onParticipantAddedDataTrack: PropTypes.func,
    /**
     * Called when a data track has been removed
     *
     * @param {{participant, track}}
     */
    onParticipantRemovedDataTrack: PropTypes.func,
    /**
     * Called when a new audio track has been added
     *
     * @param {{participant, track}}
     */
    onParticipantAddedAudioTrack: PropTypes.func,
    /**
     * Called when a audio track has been removed
     *
     * @param {{participant, track}}
     */
    onParticipantRemovedAudioTrack: PropTypes.func,
    /**
     * Called when a video track has been enabled.
     *
     * @param {{participant, track}}
     */
    onParticipantEnabledVideoTrack: PropTypes.func,
    /**
     * Called when a video track has been disabled.
     *
     * @param {{participant, track}}
     */
    onParticipantDisabledVideoTrack: PropTypes.func,
    /**
     * Called when an audio track has been enabled.
     *
     * @param {{participant, track}}
     */
    onParticipantEnabledAudioTrack: PropTypes.func,
    /**
     * Called when an audio track has been disabled.
     *
     * @param {{participant, track}}
     */
    onParticipantDisabledAudioTrack: PropTypes.func,
    /**
     * Called when an dataTrack receives a message
     *
     * @param {{message}}
     */
    onDataTrackMessageReceived: PropTypes.func,
    /**
     * Called when the camera has started
     *
     */
    onCameraDidStart: PropTypes.func,
    /**
     * Called when the camera has been interrupted
     *
     */
    onCameraWasInterrupted: PropTypes.func,
    /**
     * Called when the camera interruption has ended
     *
     */
    onCameraInterruptionEnded: PropTypes.func,
    /**
     * Called when the camera has stopped runing with an error
     *
     * @param {{error}} The error message description
     */
    onCameraDidStopRunning: PropTypes.func,
    /**
     * Called when stats are received (after calling getStats)
     *
     */
    onStatsReceived: PropTypes.func,
    /**
     * Called when the network quality levels of a participant have changed (only if enableNetworkQualityReporting is set to True when connecting)
     *
     */
    onNetworkQualityLevelsChanged: PropTypes.func,
    ...View.propTypes
  }

  constructor (props) {
    super(props)

    this._onDebugEvent = props.onDebugEvent
    this._sendDebugEvent('constructor')

    this._subscriptions = []
    this._eventEmitter = new NativeEventEmitter(TWVideoModule)

    this.setStereoEnabled = this.setStereoEnabled.bind(this)
    // We expose this to the JS layer to allow avoiding the whole custom audio device code path via CodePush update if there is a critical bug
    this.usesCustomAudioDevice = true

  }

  componentWillMount () {
    this._sendDebugEvent('componentWillMount (1/2)')
    this._registerEvents()
    this._startLocalAudio()
    this._sendDebugEvent('componentWillMount (2/2)')
  }

  componentWillUnmount () {
    this._sendDebugEvent('componentWillUnmount (1/2)')
    this._unregisterEvents()
    this._stopLocalVideo()
    this._stopLocalAudio()
    this._sendDebugEvent('componentWillUnmount (2/2)')
  }

  /**
   * Locally mute/ unmute all remote audio tracks from a given participant
   */
  setRemoteAudioPlayback ({ participantSid, enabled }) {
    this._sendDebugEvent('setRemoteAudioPlayback')
    TWVideoModule.setRemoteAudioPlayback(participantSid, enabled)
  }

  setRemoteAudioEnabled (enabled) {
    this._sendDebugEvent('setRemoteAudioEnabled: ' + (enabled ? 'true' : 'false'))
    return Promise.resolve(enabled)
  }

  setBluetoothHeadsetConnected (enabled) {
    this._sendDebugEvent('setBluetoothHeadsetConnected: ' + (enabled ? 'true' : 'false'))
    return Promise.resolve(enabled)
  }

  /**
   * Enable or disable local video
   */
  setLocalVideoEnabled (enabled) {
    this._sendDebugEvent('setLocalVideoEnabled: ' + (enabled ? 'true' : 'false'))
    this._startLocalVideo(enabled)
    return TWVideoModule.setLocalVideoEnabled(enabled)
  }

  /**
   * Enable or disable local audio
   */
  setLocalAudioEnabled (enabled) {
    this._sendDebugEvent('setLocalAudioEnabled: ' + (enabled ? 'true' : 'false'))
    return TWVideoModule.setLocalAudioEnabled(enabled)
  }

  /**
   * Enable or disable stereo mode
   */
  setStereoEnabled (enabled) {
    this._sendDebugEvent('setStereoEnabled: ' + (enabled ? 'true' : 'false'))
    return TWVideoModule.setStereoEnabled(enabled)
  }

  /**
   * Flip between the front and back camera
   */
  flipCamera () {
    this._sendDebugEvent('flipCamera')
    TWVideoModule.flipCamera()
  }

  /**
   * Toggle audio setup from speaker (default) and headset
   */
  toggleSoundSetup (speaker) {
    this._sendDebugEvent('toggleSoundSetup: ' + (speaker ? 'true' : 'false'))
    TWVideoModule.toggleSoundSetup(speaker)
  }

  /**
   * Get connection stats
   */
  getStats () {
    this._sendDebugEvent('getStats')
    TWVideoModule.getStats()
  }

  /**
   * Connect to given room name using the JWT access token
   * @param  {String} roomName    The connecting room name
   * @param  {String} accessToken The Twilio's JWT access token
   * @param  {boolean} enableVideo Don't start video unless it's necessary
   * @param  {String} encodingParameters Control Encoding config
   * @param  {Boolean} enableNetworkQualityReporting Report network quality of participants
   */
  connect ({ roomName, accessToken, enableVideo = true, encodingParameters = null, enableNetworkQualityReporting = false }) {
    this._sendDebugEvent('connect')
    TWVideoModule.connect(accessToken, roomName, enableVideo, encodingParameters, enableNetworkQualityReporting)
  }

  /**
   * Disconnect from current room
   */
  disconnect () {
    this._sendDebugEvent('disconnect')
    TWVideoModule.disconnect()
  }

  /**
   * Publish a local audio track
   */
  publishLocalAudio () {
    this._sendDebugEvent('publishLocalAudio')
    TWVideoModule.publishLocalAudio()
  }

  /**
   * Publish a local video track
   */
  publishLocalVideo () {
    this._sendDebugEvent('publishLocalVideo')
    TWVideoModule.publishLocalVideo()
  }

  /**
   * Unpublish a local audio track
   */
  unpublishLocalAudio () {
    this._sendDebugEvent('unpublishLocalAudio')
    TWVideoModule.unpublishLocalAudio()
  }

  /**
   * Unpublish a local video track
   */
  unpublishLocalVideo () {
    this._sendDebugEvent('unpublishLocalVideo')
    TWVideoModule.unpublishLocalVideo()
  }

  /**
   * SendString to datatrack
   * @param  {String} message    The message string to send
   */
  sendString (message) {
    this._sendDebugEvent('sendString')
    TWVideoModule.sendString(message)
  }

  /**
   * Send a debug event
   */
  _sendDebugEvent (ev) {
    if (this._onDebugEvent) {
      this._onDebugEvent(ev)
    }
  }

  _startLocalVideo (enabled) {
    this._sendDebugEvent('_startLocalVideo: ' + (enabled ? 'true' : 'false'))
    const screenShare = this.props.screenShare || false
    TWVideoModule.startLocalVideo(enabled)
  }

  _stopLocalVideo () {
    this._sendDebugEvent('_stopLocalVideo')
    TWVideoModule.stopLocalVideo()
  }

  _startLocalAudio () {
    this._sendDebugEvent('_startLocalAudio')
    TWVideoModule.startLocalAudio(this.usesCustomAudioDevice)
  }

  _stopLocalAudio () {
    this._sendDebugEvent('_stopLocalAudio')
    TWVideoModule.stopLocalAudio()
  }

  _unregisterEvents () {
    this._sendDebugEvent('_unregisterEvents')
    TWVideoModule.changeListenerStatus(false)
    this._subscriptions.forEach(e => e.remove())
    this._subscriptions = []
  }

  _registerEvents () {
    this._sendDebugEvent('_registerEvents')
    TWVideoModule.changeListenerStatus(true)
    this._subscriptions = [
      this._eventEmitter.addListener('roomDidConnect', data => {
        this._sendDebugEvent('native event - roomDidConnect')
        if (this.props.onRoomDidConnect) {
          this.props.onRoomDidConnect(data)
        }
      }),
      this._eventEmitter.addListener('roomDidDisconnect', data => {
        this._sendDebugEvent('native event - roomDidDisconnect')
        if (this.props.onRoomDidDisconnect) {
          this.props.onRoomDidDisconnect(data)
        }
      }),
      this._eventEmitter.addListener('roomDidFailToConnect', data => {
        this._sendDebugEvent('native event - roomDidFailToConnect')
        if (this.props.onRoomDidFailToConnect) {
          this.props.onRoomDidFailToConnect(data)
        }
      }),
      this._eventEmitter.addListener('roomParticipantDidConnect', data => {
        this._sendDebugEvent('native event - roomParticipantDidConnect')
        if (this.props.onRoomParticipantDidConnect) {
          this.props.onRoomParticipantDidConnect(data)
        }
      }),
      this._eventEmitter.addListener('roomParticipantDidDisconnect', data => {
        this._sendDebugEvent('native event - roomParticipantDidDisconnect')
        if (this.props.onRoomParticipantDidDisconnect) {
          this.props.onRoomParticipantDidDisconnect(data)
        }
      }),
      this._eventEmitter.addListener('participantAddedVideoTrack', data => {
        this._sendDebugEvent('native event - participantAddedVideoTrack')
        if (this.props.onParticipantAddedVideoTrack) {
          this.props.onParticipantAddedVideoTrack(data)
        }
      }),
      this._eventEmitter.addListener('participantAddedDataTrack', data => {
        this._sendDebugEvent('native event - participantAddedDataTrack')
        if (this.props.onParticipantAddedDataTrack) {
          this.props.onParticipantAddedDataTrack(data)
        }
      }),
      this._eventEmitter.addListener('participantRemovedDataTrack', data => {
        this._sendDebugEvent('native event - participantRemovedDataTrack')
        if (this.props.onParticipantRemovedDataTrack) {
          this.props.onParticipantRemovedDataTrack(data)
        }
      }),
      this._eventEmitter.addListener('participantRemovedVideoTrack', data => {
        this._sendDebugEvent('native event - participantRemovedVideoTrack')
        if (this.props.onParticipantRemovedVideoTrack) {
          this.props.onParticipantRemovedVideoTrack(data)
        }
      }),
      this._eventEmitter.addListener('participantAddedAudioTrack', data => {
        this._sendDebugEvent('native event - participantAddedAudioTrack')
        if (this.props.onParticipantAddedAudioTrack) {
          this.props.onParticipantAddedAudioTrack(data)
        }
      }),
      this._eventEmitter.addListener('participantRemovedAudioTrack', data => {
        this._sendDebugEvent('native event - participantRemovedAudioTrack')
        if (this.props.onParticipantRemovedAudioTrack) {
          this.props.onParticipantRemovedAudioTrack(data)
        }
      }),
      this._eventEmitter.addListener('participantEnabledVideoTrack', data => {
        this._sendDebugEvent('native event - participantEnabledVideoTrack')
        if (this.props.onParticipantEnabledVideoTrack) {
          this.props.onParticipantEnabledVideoTrack(data)
        }
      }),
      this._eventEmitter.addListener('participantDisabledVideoTrack', data => {
        this._sendDebugEvent('native event - participantDisabledVideoTrack')
        if (this.props.onParticipantDisabledVideoTrack) {
          this.props.onParticipantDisabledVideoTrack(data)
        }
      }),
      this._eventEmitter.addListener('participantEnabledAudioTrack', data => {
        this._sendDebugEvent('native event - participantEnabledAudioTrack')
        if (this.props.onParticipantEnabledAudioTrack) {
          this.props.onParticipantEnabledAudioTrack(data)
        }
      }),
      this._eventEmitter.addListener('participantDisabledAudioTrack', data => {
        this._sendDebugEvent('native event - participantDisabledAudioTrack')
        if (this.props.onParticipantDisabledAudioTrack) {
          this.props.onParticipantDisabledAudioTrack(data)
        }
      }),
      this._eventEmitter.addListener('dataTrackMessageReceived', data => {
        this._sendDebugEvent('native event - dataTrackMessageReceived')
        if (this.props.onDataTrackMessageReceived) {
          this.props.onDataTrackMessageReceived(data)
        }
      }),
      this._eventEmitter.addListener('cameraDidStart', data => {
        this._sendDebugEvent('native event - cameraDidStart')
        if (this.props.onCameraDidStart) {
          this.props.onCameraDidStart(data)
        }
      }),
      this._eventEmitter.addListener('cameraWasInterrupted', data => {
        this._sendDebugEvent('native event - cameraWasInterrupted')
        if (this.props.onCameraWasInterrupted) {
          this.props.onCameraWasInterrupted(data)
        }
      }),
      this._eventEmitter.addListener('cameraInterruptionEnded', data => {
        this._sendDebugEvent('native event - cameraInterruptionEnded')
        if (this.props.onCameraInterruptionEnded) {
          this.props.onCameraInterruptionEnded(data)
        }
      }),
      this._eventEmitter.addListener('cameraDidStopRunning', data => {
        this._sendDebugEvent('native event - cameraDidStopRunning')
        if (this.props.onCameraDidStopRunning) {
          this.props.onCameraDidStopRunning(data)
        }
      }),
      this._eventEmitter.addListener('statsReceived', data => {
        this._sendDebugEvent('native event - statsReceived')
        if (this.props.onStatsReceived) {
          this.props.onStatsReceived(data)
        }
      }),
      this._eventEmitter.addListener('networkQualityLevelsChanged', data => {
        this._sendDebugEvent('native event - networkQualityLevelsChanged')
        if (this.props.onNetworkQualityLevelsChanged) {
          this.props.onNetworkQualityLevelsChanged(data)
        }
      })
    ]
  }

  render () {
    this._sendDebugEvent('render')
    return this.props.children || null
  }
}
