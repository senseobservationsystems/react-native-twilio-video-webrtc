package com.twiliorn.library.niceday;

import static com.twiliorn.library.niceday.NDHelper.parseDimensionsString;
import static com.twiliorn.library.niceday.NDHelper.parsePriorityString;

import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.util.Log;

import androidx.annotation.Nullable;

import com.facebook.react.bridge.ReadableMap;
import com.twilio.video.BandwidthProfileMode;
import com.twilio.video.BandwidthProfileOptions;
import com.twilio.video.ConnectOptions;
import com.twilio.video.EncodingParameters;
import com.twilio.video.RemoteParticipant;
import com.twilio.video.RemoteVideoTrack;
import com.twilio.video.RemoteVideoTrackPublication;
import com.twilio.video.Room;
import com.twilio.video.TrackPriority;
import com.twilio.video.TrackSwitchOffMode;
import com.twilio.video.VideoBandwidthProfileOptions;
import com.twilio.video.VideoDimensions;

import java.util.HashMap;
import java.util.Map;

/**
 * This class contains changes on CustomTwilioVideoView.
 * We put it on separate file to minimizes conflict when merging from upstream.
 * NOTE: This class should only be used on CustomTwilioVideoView.
 */
public class NDExtra {
    public static final String BT_INTENT = "com.twiliorn.library.niceday.bluetooth";
    private static final String TAG = "BandwidthProfile";
    private static final VideoDimensions DEFAULT_MAX_CAPTURE_RESOLUTION = VideoDimensions.CIF_VIDEO_DIMENSIONS;
    private static final int DEFAULT_MAX_CAPTURE_FPS = 25;
    public boolean enableH264Codec = false;
    public int audioBitrate = 0;
    public int videoBitrate = 0;
    public BandwidthProfileOptions bandwidthProfile = null;
    public boolean isVideoEnabled;
    public VideoDimensions maxCaptureDimensions = DEFAULT_MAX_CAPTURE_RESOLUTION;
    public int maxCaptureFPS = DEFAULT_MAX_CAPTURE_FPS;
    Context appContext;
    Handler handler = new Handler();
    int delay = 2000;
    Runnable run = new Runnable() {
        public void run() {
            Log.d(TAG,"RUNNING");
            Intent intent = new Intent(BT_INTENT);
            appContext.sendBroadcast(intent);
            handler.postDelayed(this, delay);
        }
    };

    public NDExtra(Context appContext) {
        this.appContext = appContext;
        btHeadsetListener();
    }

    public BandwidthProfileOptions prepareBandwidthProfile(ReadableMap options) {
        BandwidthProfileMode mode = null;
        TrackSwitchOffMode trackSwitchOffMode = null;
        @Nullable Long maxTracks = null;
        @Nullable Long maxSubscriptionBitrate = null;
        TrackPriority dominantSpeakerPriority = null;
        Map<TrackPriority, VideoDimensions> renderDimensions = new HashMap<>();

        if (options.hasKey("mode")) {
            String modeString = options.getString("mode");

            // Parse mode of the current call
            if (modeString != null) {
                if (modeString.equalsIgnoreCase("GRID")) {
                    mode = BandwidthProfileMode.GRID;
                } else if (modeString.equalsIgnoreCase("COLLABORATION")) {
                    mode = BandwidthProfileMode.COLLABORATION;
                } else if (modeString.equalsIgnoreCase("PRESENTATION")) {
                    mode = BandwidthProfileMode.PRESENTATION;
                } else {
                    Log.w(TAG, "Unknown Bandwidth Profile Mode" + modeString);
                }
            }
        }

        if (options.hasKey("trackSwitchOffMode")) {
            String trackSwitchOffModeString = options.getString("trackSwitchOffMode");

            // Parse mode of the current call
            if (trackSwitchOffModeString != null) {
                if (trackSwitchOffModeString.equalsIgnoreCase("DISABLED")) {
                    trackSwitchOffMode = TrackSwitchOffMode.DISABLED;
                } else if (trackSwitchOffModeString.equalsIgnoreCase("PREDICTED")) {
                    trackSwitchOffMode = TrackSwitchOffMode.PREDICTED;
                } else if (trackSwitchOffModeString.equalsIgnoreCase("DETECTED")) {
                    trackSwitchOffMode = TrackSwitchOffMode.DETECTED;
                } else {
                    Log.w(TAG, "Unknown Track Switch Off Mode" + trackSwitchOffModeString);
                }
            }
        }

        // Parse max tracks to enabled during a call
        if (options.hasKey("maxTracks")) {
            int maxTracksAsInt = options.getInt("maxTracks");
            if (maxTracksAsInt > 0) {
                maxTracks = (long) maxTracksAsInt;
            }
        }

        // Parse max subscription bit rate
        if (options.hasKey("maxSubscriptionBitrate")) {
            int maxSubscriptionBitrateAsInt = options.getInt("maxSubscriptionBitrate");
            if (maxSubscriptionBitrateAsInt > 0) {
                maxSubscriptionBitrate = (long) maxSubscriptionBitrateAsInt;
            }
        }

        // Parse priority for dominant speaker
        if (options.hasKey("dominantSpeakerPriority")) {
            dominantSpeakerPriority = parsePriorityString(options.getString("dominantSpeakerPriority"));
        }

        // Parse Render Dimensions
        if (options.hasKey("renderDimensions")) {
            ReadableMap renderDimensionsMap = options.getMap("renderDimensions");
            if (renderDimensionsMap != null) {
                if (renderDimensionsMap.hasKey("low")) {
                    VideoDimensions dimensions = parseDimensionsString(renderDimensionsMap.getString("low"));
                    if (dimensions != null) {
                        renderDimensions.put(TrackPriority.LOW, dimensions);
                    }
                }

                if (renderDimensionsMap.hasKey("standard")) {
                    VideoDimensions dimensions = parseDimensionsString(renderDimensionsMap.getString("standard"));
                    if (dimensions != null) {
                        renderDimensions.put(TrackPriority.STANDARD, dimensions);
                    }
                }

                if (renderDimensionsMap.hasKey("high")) {
                    VideoDimensions dimensions = parseDimensionsString(renderDimensionsMap.getString("high"));
                    if (dimensions != null) {
                        renderDimensions.put(TrackPriority.HIGH, dimensions);
                    }
                }
            }
        } else {
            this.isVideoEnabled = false;
        }

        Log.d(TAG, "BandwidthProfile - mode: " + mode);
        Log.d(TAG, "BandwidthProfile - maxTracks: " + maxTracks);
        Log.d(TAG, "BandwidthProfile - dominantSpeakerPriority: " + dominantSpeakerPriority);
        Log.d(TAG, "BandwidthProfile - renderDimensions: " + renderDimensions);
        Log.d(TAG, "BandwidthProfile - trackSwitchOffMode: " + trackSwitchOffMode);

        VideoBandwidthProfileOptions videoBandwidthProfileOptions = new VideoBandwidthProfileOptions.Builder()
                .mode(mode)
                .maxTracks(maxTracks)
                .dominantSpeakerPriority(dominantSpeakerPriority)
                .maxSubscriptionBitrate(maxSubscriptionBitrate)
                .renderDimensions(renderDimensions)
                .trackSwitchOffMode(trackSwitchOffMode)
                .build();
        return new BandwidthProfileOptions(videoBandwidthProfileOptions);
    }

    public void applyExtraParamsTo(ConnectOptions.Builder connectOptionsBuilder) {
        // If we have specified bit rates then use them
        if (this.audioBitrate >= 0 && this.videoBitrate >= 0) {
            connectOptionsBuilder.encodingParameters(new EncodingParameters(this.audioBitrate, this.videoBitrate));
            Log.d(TAG, "Setting max audio rate" + this.audioBitrate + " and max video rate: " + this.videoBitrate);
        } else {
            // If we have specified only 1 of the bit rate values
            if (this.audioBitrate >= 0 || this.videoBitrate >= 0) {
                // Then warn the user that we are ignoring the value
                Log.w(TAG, "Ignoring audio or video bitrate as only 1 of them is defined. Audio: " + this.audioBitrate + " Video:" + this.videoBitrate);
            }
        }
        connectOptionsBuilder.bandwidthProfile(this.bandwidthProfile);
    }

    public void setExtraParams(ReadableMap encodingParameters, ReadableMap bandwidthProfileOptions) {
        if (encodingParameters.hasKey("enableH264Codec")) {
            this.enableH264Codec = encodingParameters.getBoolean("enableH264Codec");
        }

        if (encodingParameters.hasKey("audioBitrate")) {
            this.audioBitrate = encodingParameters.getInt("audioBitrate");
        }

        if (encodingParameters.hasKey("videoBitrate")) {
            this.videoBitrate = encodingParameters.getInt("videoBitrate");
        }

        this.bandwidthProfile = prepareBandwidthProfile(bandwidthProfileOptions);
    }

    public void applyCameraSettings(ReadableMap cameraSettings) {
        if (cameraSettings != null) {
            if (cameraSettings.hasKey("maxDimensions")) {
                this.maxCaptureDimensions = parseDimensionsString(cameraSettings.getString("maxDimensions"));
            }

            if (cameraSettings.hasKey("maxFPS")) {
                this.maxCaptureFPS = cameraSettings.getInt("maxFPS");
            }
        }

        if (this.maxCaptureDimensions == null) {
            this.maxCaptureDimensions = DEFAULT_MAX_CAPTURE_RESOLUTION;
        }

        if (this.maxCaptureFPS < 1) {
            this.maxCaptureFPS = DEFAULT_MAX_CAPTURE_FPS;
        }
    }

    public void setTrackPriority(String trackSid, String trackPriorityString, Room room) {
        TrackPriority priority = parsePriorityString(trackPriorityString);

        for (RemoteParticipant participant : room.getRemoteParticipants()) {
            for (RemoteVideoTrackPublication publication : participant.getRemoteVideoTracks()) {
                RemoteVideoTrack track = publication.getRemoteVideoTrack();
                if (track == null) {
                    continue;
                }
                if (publication.getTrackSid().equals(trackSid)) {
                    track.setPriority(priority);
                }
            }
        }
    }

    public void cleanUp() {
        try {
            handler.removeCallbacksAndMessages(null);
            Log.d(TAG,"cleanup");
        } catch (Exception ignored) {
            Log.d(TAG,ignored.getMessage());
        }
    }

    public void btHeadsetListener() {
        handler.postDelayed(run, delay);
    }
}
