/**
 * Wrapper component for the Twilio Video View to facilitate easier layout.
 * <p>
 * Author:
 * Jonathan Chang <slycoder@gmail.com>
 */
package com.twiliorn.library;

import android.content.Context;
import android.graphics.Point;
import android.view.View;
import android.view.ViewGroup;
import androidx.annotation.StringDef;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.uimanager.UIManagerModule;
import com.facebook.react.uimanager.events.EventDispatcher;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.WritableNativeMap;
import com.facebook.react.uimanager.ThemedReactContext;
import com.facebook.react.uimanager.events.RCTEventEmitter;
import com.twilio.video.VideoFrame;
import com.twilio.video.VideoRenderer;
import com.twilio.video.VideoScaleType;

import org.webrtc.RendererCommon;

import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

import static com.twiliorn.library.RNVideoViewGroup.Events.ON_FRAME_DIMENSIONS_CHANGED;

public class RNVideoViewGroup extends ViewGroup {
    private PatchedVideoView surfaceViewRenderer = null;
    private int videoWidth = 0;
    private int videoHeight = 0;
    private final Object layoutSync = new Object();
    private int scalesType = 0;
    private RendererCommon.ScalingType scalingType = RendererCommon.ScalingType.SCALE_ASPECT_FILL;
    private final RCTEventEmitter eventEmitter;

    @Retention(RetentionPolicy.SOURCE)
    @StringDef({ON_FRAME_DIMENSIONS_CHANGED})
    public @interface Events {
        String ON_FRAME_DIMENSIONS_CHANGED = "onFrameDimensionsChanged";
    }

    void pushEvent(View view, String name, WritableMap data) {
        ReactContext context= (ReactContext) view.getContext();
        EventDispatcher eventDispatcher =
                context.getNativeModule(UIManagerModule.class).getEventDispatcher();
        eventDispatcher.dispatchEvent(new TwilioEvent(view.getId(),name,data));
    }

    public RNVideoViewGroup(ThemedReactContext themedReactContext) {
        super(themedReactContext);
        this.eventEmitter = themedReactContext.getJSModule(RCTEventEmitter.class);
        surfaceViewRenderer = new PatchedVideoView(themedReactContext);
        surfaceViewRenderer.setVideoScaleType(VideoScaleType.ASPECT_FILL);
        addView(surfaceViewRenderer);
        surfaceViewRenderer.setListener(
                new VideoRenderer.Listener() {
                    @Override
                    public void onFirstFrame() {

                    }

                    @Override
                    public void onFrameDimensionsChanged(int vw, int vh, int rotation) {
                        synchronized (layoutSync) {
                            if (rotation == VideoFrame.RotationAngle.ROTATION_90.getValue() ||
                                    rotation == VideoFrame.RotationAngle.ROTATION_270.getValue()) {
                                videoHeight = vw;
                                videoWidth = vh;
                            } else {
                                videoHeight = vh;
                                videoWidth = vw;
                            }
                            RNVideoViewGroup.this.forceLayout();

                            WritableMap event = new WritableNativeMap();
                            event.putInt("height", vh);
                            event.putInt("width", vw);
                            event.putInt("rotation", rotation);
                            pushEvent(RNVideoViewGroup.this, ON_FRAME_DIMENSIONS_CHANGED, event);
                        }
                    }
                }
        );
    }

    public PatchedVideoView getSurfaceViewRenderer() {
        return surfaceViewRenderer;
    }

    public void setScalingType(RendererCommon.ScalingType scalingType) {
        this.scalingType = scalingType;
    }

    public void setScalesType(int scalesType) {
        this.scalesType = scalesType;
    }

    @Override
    protected void onLayout(boolean changed, int l, int t, int r, int b) {
        int height = b - t;
        int width = r - l;
        if (height == 0 || width == 0) {
            l = t = r = b = 0;
        } else {
            RendererCommon.ScalingType overriddenScaleType;
            int videoHeight;
            int videoWidth;

            synchronized (layoutSync) {
                videoHeight = this.videoHeight;
                videoWidth = this.videoWidth;
            }

            if (videoHeight == 0 || videoWidth == 0) {
                // These are Twilio defaults.
                videoHeight = 480;
                videoWidth = 640;
            }

            if (this.scalesType == 1) overriddenScaleType = RendererCommon.ScalingType.SCALE_ASPECT_FIT;
            else overriddenScaleType = RendererCommon.ScalingType.SCALE_ASPECT_FILL;

            Point displaySize = RendererCommon.getDisplaySize(
                    overriddenScaleType,
                    videoWidth / (float) videoHeight,
                    width,
                    height
            );

            l = (width - displaySize.x) / 2;
            t = (height - displaySize.y) / 2;
            r = l + displaySize.x;
            b = t + displaySize.y;
        }
        surfaceViewRenderer.layout(l, t, r, b);
    }

    // requestLayout and measureAndLayout is a hack to make sure that
    // layout is always triggered whenever one of the props is changing
    @Override
    public void requestLayout() {
        super.requestLayout();
        post(measureAndLayout);
    }

    private final Runnable measureAndLayout = new Runnable() {
        @Override
        public void run() {
            measure(
                MeasureSpec.makeMeasureSpec(getWidth(), MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(getHeight(), MeasureSpec.EXACTLY));
            layout(getLeft(), getTop(), getRight(), getBottom());
        }
    };
}
