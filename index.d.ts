declare module "react-native-twilio-video-webrtc" {
  import { ViewProps } from "react-native";
  import React from "react";

  export interface TrackIdentifier {
    participantSid: string;
    videoTrackSid: string;
  }

  type scaleType = "fit" | "fill";
  type cameraType = "front" | "back";

  interface TwilioVideoParticipantViewProps extends ViewProps {
    trackIdentifier: TrackIdentifier;
    ref?: React.Ref<any>;
    scalesType?: number;
    scaleType?: scaleType;
    applyZOrder?: boolean;
  }

  interface TwilioVideoLocalViewProps extends ViewProps {
    enabled: boolean;
    ref?: React.Ref<any>;
    scalesType?: number;
    scaleType?: scaleType;
    applyZOrder?: boolean;
  }

  export interface Participant {
    sid: string;
    identity: string;
  }

  export interface Track {
    enabled: boolean;
    trackName: string;
    trackSid: string;
  }

  export interface TrackEventCbArgs {
    participant: Participant;
    track: Track;
  }

  export type TrackEventCb = (t: TrackEventCbArgs) => void;

  export interface DataTrackEventCbArgs {
    message: string;
    trackSid: string;
  }

  export type DataTrackEventCb = (t: DataTrackEventCbArgs) => void;

  interface RoomEventCommonArgs {
    roomName: string;
    roomSid: string;
  }

  export type RoomErrorEventArgs = RoomEventCommonArgs & {
    error: any;
  };

  type RoomEventArgs = RoomEventCommonArgs & {
    participants: Participant[];
    localParticipant: Participant;
  };

  type ParticipantEventArgs = RoomEventCommonArgs & {
    participant: Participant;
  };

  type NetworkLevelChangeEventArgs = {
    participant: Participant;
    isLocalUser: boolean;
    quality: number;
  };

  export type RoomEventCb = (p: RoomEventArgs) => void;
  export type RoomErrorEventCb = (t: RoomErrorEventArgs) => void;

  export type ParticipantEventCb = (p: ParticipantEventArgs) => void;
  
  export type NetworkLevelChangeEventCb = (p: NetworkLevelChangeEventArgs) => void;

  export type DominantSpeakerChangedEventArgs = RoomEventCommonArgs & {
    participant: Participant;
  }
  
  export type DominantSpeakerChangedCb = (d: DominantSpeakerChangedEventArgs) => void;

  export type LocalParticipantSupportedCodecsCbEventArgs = {
    supportedCodecs: Array<string>;
  }

  export type LocalParticipantSupportedCodecsCb = (d: LocalParticipantSupportedCodecsCbEventArgs) => void;

  export type TwilioVideoProps = ViewProps & {
    onCameraDidStart?: () => void;
    onCameraDidStopRunning?: (err: any) => void;
    onCameraWasInterrupted?: () => void;
    onDominantSpeakerDidChange?: DominantSpeakerChangedCb;
    onParticipantAddedAudioTrack?: TrackEventCb;
    onParticipantAddedVideoTrack?: TrackEventCb;
    onParticipantDisabledVideoTrack?: TrackEventCb;
    onParticipantDisabledAudioTrack?: TrackEventCb;
    onParticipantEnabledVideoTrack?: TrackEventCb;
    onParticipantEnabledAudioTrack?: TrackEventCb;
    onParticipantRemovedAudioTrack?: TrackEventCb;
    onParticipantRemovedVideoTrack?: TrackEventCb;
    onParticipantAddedDataTrack?: TrackEventCb;
    onParticipantRemovedDataTrack?: TrackEventCb;
    onRoomDidConnect?: RoomEventCb;
    onRoomDidDisconnect?: RoomErrorEventCb;
    onRoomDidFailToConnect?: RoomErrorEventCb;
    onRoomParticipantDidConnect?: ParticipantEventCb;
    onRoomParticipantDidDisconnect?: ParticipantEventCb;
    onNetworkQualityLevelsChanged?: NetworkLevelChangeEventCb;
    onLocalParticipantSupportedCodecs?: LocalParticipantSupportedCodecsCb;

    onStatsReceived?: (data: any) => void;
    onDataTrackMessageReceived?: DataTrackEventCb;

    useCustomAudioDevice?: boolean;

    // iOS only
    autoInitializeCamera?: boolean;    
    ref?: React.Ref<any>;
  };

  export type BandwidthProfileMode = "GRID" | "COLLABORATION" | "PRESENTATION";

  export type TrackPriority = "LOW" | "STANDARD" | "HIGH" | "NULL";

  export type TrackSwitchOffMode = "DISABLED" | "PREDICTED" | "DETECTED";

  export type CameraSettings = {
    maxDimensions: string;
    maxFPS: number;
  };

  // Dimensions are provided in the string in the format of <width>x<height>
  export type RenderDimensions = {
    "low"?: string,
    "standard"?: string,
    "high"?: string,
  }

  export type BandwidthProfileOptions = {
    mode?: BandwidthProfileMode
    maxTracks?: number,
    maxSubscriptionBitrate?: number,
    dominantSpeakerPriority?: TrackPriority,
    renderDimensions?: RenderDimensions,
    trackSwitchOffMode?: TrackSwitchOffMode,
  }

  type iOSConnectParams = {
    roomName?: string;
    accessToken: string;
    cameraType?: cameraType;
    dominantSpeakerEnabled?: boolean;
    enableAudio?: boolean;
    enableVideo?: boolean;
    encodingParameters?: {
      enableH264Codec?: boolean;
      // if audioBitrate OR videoBitrate is provided, you must provide both
      audioBitrate?: number;
      videoBitrate?: number;
    };
    enableNetworkQualityReporting?: boolean;
    bandwidthProfileOptions?: BandwidthProfileOptions;
  };

  type androidConnectParams = {
    roomName?: string;
    accessToken: string;
    cameraType?: cameraType;
    dominantSpeakerEnabled?: boolean;
    enableAudio?: boolean;
    enableVideo?: boolean;
    encodingParameters?: {
      enableH264Codec?: boolean;
      // if audioBitrate OR videoBitrate is provided, you must provide both
      audioBitrate?: number;
      videoBitrate?: number;
    };
    enableRemoteAudio?: boolean;
    enableNetworkQualityReporting?: boolean;
    maintainVideoTrackInBackground?: boolean;
    bandwidthProfileOptions?: BandwidthProfileOptions;
  };

  class TwilioVideo extends React.Component<TwilioVideoProps> {
    setLocalVideoEnabled: (enabled: boolean, cameraSettings?: CameraSettings) => Promise<boolean>;
    setLocalAudioEnabled: (enabled: boolean) => Promise<boolean>;
    setRemoteAudioEnabled: (enabled: boolean) => Promise<boolean>;
    setBluetoothHeadsetConnected: (enabled: boolean) => Promise<boolean>;
    connect: (options: iOSConnectParams | androidConnectParams) => void;
    disconnect: () => void;
    flipCamera: () => void;
    toggleSoundSetup: (speaker: boolean) => void;
    getStats: () => void;
    publishLocalAudio: () => void;
    unpublishLocalAudio: () => void;
    publishLocalVideo: () => void;
    unpublishLocalVideo: () => void;
    sendString: (message: string) => void;
    setStereoEnabled: (enabled: boolean) => Promise<boolean>;
    setTrackPriority: (trackSid: string, trackPriority: TrackPriority) => void;
  }

  class TwilioVideoLocalView extends React.Component<
    TwilioVideoLocalViewProps
  > {}

  class TwilioVideoParticipantView extends React.Component<
    TwilioVideoParticipantViewProps
  > {}

  export { TwilioVideoLocalView, TwilioVideoParticipantView, TwilioVideo };

  export class TwilioStereoTonePlayer {
    preload: (filename: string) => Promise<boolean>;
    play: (filename: string, isLooping: boolean, volume: number, playbackSpeed: number) => Promise<void>;
    pause: () => void;
    setVolume: (volume: number) => void;
    setPlaybackSpeed: (speed: number) => void;
    release: (filename: string) => void;
    terminate: () => void;
  }
}
