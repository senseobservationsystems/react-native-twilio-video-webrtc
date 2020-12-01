package com.twiliorn.library;

import android.util.Log;

import com.facebook.react.bridge.WritableMap;
import com.facebook.react.uimanager.events.Event;
import com.facebook.react.uimanager.events.RCTEventEmitter;

public class TwilioEvent extends Event<TwilioEvent> {
    private  WritableMap event;
    private String eventName;
    @Override
    public String getEventName() {
        return eventName;
    }
    public TwilioEvent(int viewId, String eventName, WritableMap event) {
        super.init(viewId);
        this.event=event;
        this.eventName=eventName;
    }

    @Override
    public void dispatch(RCTEventEmitter rctEventEmitter) {
        rctEventEmitter.receiveEvent(getViewTag(), eventName, event);
    }
}