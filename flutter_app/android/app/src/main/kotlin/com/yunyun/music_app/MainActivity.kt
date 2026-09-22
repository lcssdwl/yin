package com.yunyun.music_app

// 注意:audio_service 要求 Activity 必须继承 AudioServiceActivity,
// 否则会报 "The Activity class declared in your AndroidManifest.xml is wrong
// or has not provided the correct FlutterEngine",系统媒体通知无法启动。
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()
