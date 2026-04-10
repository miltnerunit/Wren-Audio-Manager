package com.soundtest.app

import android.app.Application

class SoundTestApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AudioManager.init(this)
    }
}
