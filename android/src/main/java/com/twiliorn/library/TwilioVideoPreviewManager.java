/**
 * Component for Twilio Video local views.
 * <p>
 * Authors:
 * Jonathan Chang <slycoder@gmail.com>
 */

package com.twiliorn.library;

import androidx.annotation.Nullable;

import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.common.MapBuilder;
import com.facebook.react.uimanager.SimpleViewManager;
import com.facebook.react.uimanager.ThemedReactContext;
import com.facebook.react.uimanager.annotations.ReactProp;

import java.util.Map;

import org.webrtc.RendererCommon;

public class TwilioVideoPreviewManager extends SimpleViewManager<TwilioVideoPreview> {

    public static final String REACT_CLASS = "RNTwilioVideoPreview";

    @Override
    public String getName() {
        return REACT_CLASS;
    }

    @ReactProp(name = "scaleType")
    public void setScaleType(TwilioVideoPreview view, @Nullable String scaleType) {
      if (scaleType.equals("fit")) {
        view.setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FIT);
      } else {
        view.setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL);
      }
    }

    @ReactProp(name = "scalesType")
    public void setScalesType(TwilioVideoPreview view, @Nullable int scalesType) {
        // This props is made specially for nice day to allow double tapping to change the video size.
        // Details: https://github.com/senseobservationsystems/goalie-2-mobile-app/pull/2941
        // We add request layout at the end of the function to always trigger layouting whenever
        // value of this props changes.
        view.setScalesType(scalesType);
        view.requestLayout();
    }

    @ReactProp(name = "onTop")
    public void setOnTop(TwilioVideoPreview view, @Nullable boolean onTop) {
        if (onTop) {
            view.applyZOrder();
        }
    }

    @Override
    protected TwilioVideoPreview createViewInstance(ThemedReactContext reactContext) {
        return new TwilioVideoPreview(reactContext);
    }
}
