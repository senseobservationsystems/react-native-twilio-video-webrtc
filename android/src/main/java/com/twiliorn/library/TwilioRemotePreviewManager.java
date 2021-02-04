/**
 * Component for Twilio Video participant views.
 * <p>
 * Authors:
 * Jonathan Chang <slycoder@gmail.com>
 */

package com.twiliorn.library;

import androidx.annotation.Nullable;
import android.util.Log;

import com.facebook.react.common.MapBuilder;
import com.facebook.react.uimanager.SimpleViewManager;
import com.facebook.react.uimanager.ThemedReactContext;
import com.facebook.react.uimanager.annotations.ReactProp;

import org.webrtc.RendererCommon;

import java.util.Map;

import static com.twiliorn.library.RNVideoViewGroup.Events.ON_FRAME_DIMENSIONS_CHANGED;

public class TwilioRemotePreviewManager extends SimpleViewManager<TwilioRemotePreview> {

    public static final String REACT_CLASS = "RNTwilioRemotePreview";
    public String myTrackSid = "";

    @Override
    public String getName() {
        return REACT_CLASS;
    }

    @ReactProp(name = "scaleType")
    public void setScaleType(TwilioRemotePreview view, @Nullable String scaleType) {
      if (scaleType.equals("fit")) {
        view.setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FIT);
      } else {
        view.setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL);
      }
    }

    @ReactProp(name = "scalesType")
    public void setScalesType(TwilioRemotePreview view, @Nullable int scalesType) {
        // This props is made specially for nice day to allow double tapping to change the video size.
        // Details: https://github.com/senseobservationsystems/goalie-2-mobile-app/pull/2941
        // We add request layout at the end of the function to always trigger layouting whenever
        // value of this props changes.
        view.setScalesType(scalesType);
        view.requestLayout();
    }

    @ReactProp(name = "trackSid")
    public void setTrackId(TwilioRemotePreview view, @Nullable String trackSid) {
        Log.i("CustomTwilioVideoView", "Initialize Twilio REMOTE");
        Log.i("CustomTwilioVideoView", trackSid);
        myTrackSid = trackSid;
        CustomTwilioVideoView.registerPrimaryVideoView(view.getSurfaceViewRenderer(), trackSid);
    }

    @Override
    protected TwilioRemotePreview createViewInstance(ThemedReactContext reactContext) {
        return new TwilioRemotePreview(reactContext, myTrackSid);
    }

    @Override
    public Map getExportedCustomBubblingEventTypeConstants() {
      return MapBuilder.builder()
          .put(
            ON_FRAME_DIMENSIONS_CHANGED,
              MapBuilder.of(
                  "phasedRegistrationNames",
                  MapBuilder.of("bubbled", ON_FRAME_DIMENSIONS_CHANGED)))
                  .build();
  }
}
