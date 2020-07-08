package com.twiliorn.library;

import android.content.res.AssetFileDescriptor;
import android.media.AudioManager;
import android.media.SoundPool;
import android.net.Uri;
import android.util.Log;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

public class TwilioStereoTonePlayer extends ReactContextBaseJavaModule implements SoundPool.OnLoadCompleteListener {

    private static final String TAG = "TwilioStereoTonePlayer";

    // An instance to the SoundPool android class for playing small audio files efficiently
    private SoundPool soundPool;
    private int maxLoadableFiles;

    // A class to store information about a loaded/loading tone file
    private class ToneFile {
        int id = -1;
        boolean loop = false;

        boolean isPlaying = false;

        Promise loadingPromise = null;
    }

    // A map containing FileName and ToneFile instances for all files that are called with preload
    private Map<String, ToneFile> loadedFiles;

    // Properties for currently playing file
    private int currentPlayingFile = -1;
    private float volume = 1.0f;
    private float playbackSpeed = 1.0f;

    ///// Methods
    public TwilioStereoTonePlayer(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    @Override
    public String getName() {
        return TAG;
    }

    @ReactMethod
    public void initialize(int maxLoadableFiles) {
        this.maxLoadableFiles = maxLoadableFiles;

        loadedFiles = new HashMap<String, ToneFile>(maxLoadableFiles);
        this.soundPool = new SoundPool(
                maxLoadableFiles, AudioManager.STREAM_MUSIC, 0);
        this.soundPool.setOnLoadCompleteListener(this);
    }

    @ReactMethod
    public void preload(String filename, Promise promise) {
        Log.v(TAG,"preload " + filename);

        // Sanity Check
        if (this.soundPool == null || this.loadedFiles == null) {
            promise.reject("Error", "Please call initialize first");
            return;
        }

        if (this.loadedFiles.size() > maxLoadableFiles) {
            promise.reject("Error", "Trying to load more files than you called Initialize with! Already loaded " + maxLoadableFiles + " files.");
        }

        if (this.loadedFiles.containsKey(filename)) {
            promise.resolve(true);
            return;
        }

        // Create an asset file descriptor
        AssetFileDescriptor assetFile;

        // Note: We only try/catch this block to make sure promise.reject is only called once
        // Otherwise its possible for the promise to be rejected in onLoadComplete
        try {
            assetFile = getReactApplicationContext().getAssets().openFd(filename);
        }  catch (Exception e) {
            promise.reject("error", "Unable to load file: " + filename, e);
            return;
        }

        // Generate a ToneFile object
        ToneFile toneFile = new ToneFile();
        toneFile.loadingPromise = promise;

        // Store in the loaded files map
        this.loadedFiles.put(filename, toneFile);

        // SoundPool.Load is an async function and will return its result in onLoadComplete
        toneFile.id = soundPool.load(assetFile, 1);

        // Note: We don't resolve the promises in this function
        // The promises are only resolved in onLoadComplete
    }

    @ReactMethod
    public void play(String filename, boolean isLooping, float volume, float playbackSpeed, Promise promise) {
        Log.v(TAG,String.format("Playing %s isLooping %b volume %f speed %f", filename, isLooping, volume, playbackSpeed));

        // Sanity Check
        if (this.soundPool == null || this.loadedFiles == null) {
            promise.reject("Error", "Please call initialize first");
            return;
        }

        if (!this.loadedFiles.containsKey(filename)) {
            this.preload(filename, promise);

            // If we still don't have the file in the loaded files array, then the promise must have been returned by this.preload so lets just exit
            if (!this.loadedFiles.containsKey(filename)) {
                return;
            }
        }

        ToneFile toneFile = this.loadedFiles.get(filename);

        // We clear the object with the promise when the file is fully loaded, so if the loadingPromise is null that means we are still loading the file
        if (toneFile.loadingPromise != null) {
            promise.reject("Error", "File is not loading yet. " + filename);
            return;
        }

        // Before we play a new tone, lets make sure we pause any tone that is currently playing
        this.pause();

        // Time To Loop. 0 = Loop only once | -1 = Loop infinitely.
        int timesToLoop = 0;
        if (isLooping) {
            timesToLoop = -1;
        }

        this.volume = volume;
        this.playbackSpeed = playbackSpeed;

        this.soundPool.play(toneFile.id, this.volume, this.volume, 1, timesToLoop, this.playbackSpeed);
        currentPlayingFile = toneFile.id;
    }

    @ReactMethod
    public void pause() {
        Log.v(TAG,"Pause");

        // Sanity Check
        if (this.soundPool == null && this.loadedFiles == null)
            return;

        if (currentPlayingFile >= 0) {
            this.soundPool.pause(currentPlayingFile);
            currentPlayingFile = -1;
        }
    }

    @ReactMethod
    public void setVolume(float volume) {
        Log.v(TAG,"setVolume " + volume);

        // Sanity Check
        if (this.soundPool == null && this.loadedFiles == null)
            return;

        this.volume = volume;

        // If we are playing a file when setVolume is called then make sure we update its volume
        if (currentPlayingFile >= 0) {
            this.soundPool.setVolume(currentPlayingFile, this.volume, this.volume);
        }
    }

    @ReactMethod
    public void setPlaybackSpeed(float speed) {
        Log.v(TAG,"setPlaybackSpeed " + speed);

        // Sanity Check
        if (this.soundPool == null && this.loadedFiles == null)
            return;

        if (this.playbackSpeed > 2.0f) {
            Log.w(TAG, "Max Playback Speed of 2.0 is supported, you tried " + this.playbackSpeed);
        } else if (this.playbackSpeed < 0.5f) {
            Log.w(TAG, "Min Playback Speed of 0.5 is supported, you tried " + this.playbackSpeed);
        }

        this.playbackSpeed = speed;

        // If we are playing a file when setVolume is called then make sure we update its volume
        if (currentPlayingFile >= 0) {
            this.soundPool.setRate(currentPlayingFile, this.playbackSpeed);
        }
    }

    @ReactMethod
    public void release(String filename) {
        Log.v(TAG,"release " + filename);

        // Sanity Check
        if (this.soundPool == null && this.loadedFiles == null)
            return;

        if (loadedFiles.containsKey(filename)) {
            ToneFile toneFile = this.loadedFiles.get(filename);

            // If this file was currently playing, then pause the player
            if (currentPlayingFile == toneFile.id) {
                pause();
            }

            // Remove all memory related to this file
            this.soundPool.unload(toneFile.id);
            this.loadedFiles.remove(filename);
        }
    }

    @ReactMethod
    public void terminate() {
        Log.v(TAG,"terminate");

        // Make sure we pause any audio that might be being played right now
        pause();

        // Free all allocated memory
        this.loadedFiles.clear();
        this.loadedFiles = null;

        this.soundPool.release();
        this.soundPool = null;
    }

    //////////// Sound Pool Methods ////////////
    @Override
    public void onLoadComplete(SoundPool soundPool, int id, int status) {

        // Loop through all files in the loaded files map
        Iterator it = loadedFiles.entrySet().iterator();
        while (it.hasNext()) {
            Map.Entry pair = (Map.Entry)it.next();

            // Get the current iterations key (file path), value (ToneFile object)
            String filePath = (String)pair.getKey();
            ToneFile toneFile = (ToneFile)pair.getValue();

            // If its the same file as the one that was just loaded
            if (toneFile.id == id) {
                // Check if the file that was just loaded was loaded successfully
                // Note: Status 0 = success, everything else = failed
                if (status == 0) {
                    // Mark the file to be loaded correctly
                    toneFile.loadingPromise.resolve(true);

                    // Free the reference to the loading promise so garbage collector can clean it later
                    toneFile.loadingPromise = null;
                } else {
                    // Reject the promise
                    toneFile.loadingPromise.reject("Error", "Error loading file with path: " + filePath);
                    toneFile.loadingPromise = null;

                    // Remove the entry of the current file from the loadedFiles map
                    it.remove();
                }

                // As LoadComplete is called once per file, we can just exit the loop
                break;
            }
        }
    }
}