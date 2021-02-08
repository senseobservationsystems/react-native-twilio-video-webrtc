/**
 * Component for Twilio Video local views.
 * <p>
 * Authors:
 * Jonathan Chang <slycoder@gmail.com>
 */

package com.twiliorn.library;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.uimanager.ThemedReactContext;

public class TwilioVideoPreview extends RNVideoViewGroup {

    private static final String TAG = "TwilioVideoPreview";

    public TwilioVideoPreview(ThemedReactContext themedReactContext) {
        super(themedReactContext);
        CustomTwilioVideoView.registerThumbnailVideoView(this.getSurfaceViewRenderer());
    }

    // Previously, we always call this function for all Local Video.
    // But, this results in a problem where camera view can be rendered below
    // Local Video on the middle of Call Screen.
    public void applyZOrder() {
        this.getSurfaceViewRenderer().applyZOrder(true);
    }
}
