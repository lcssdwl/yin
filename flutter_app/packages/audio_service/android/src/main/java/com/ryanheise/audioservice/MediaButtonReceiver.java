package com.ryanheise.audioservice;

import android.content.Context;
import android.content.Intent;

public class MediaButtonReceiver extends androidx.media.session.MediaButtonReceiver {
    public static final String ACTION_NOTIFICATION_DELETE = "com.ryanheise.audioservice.intent.action.ACTION_NOTIFICATION_DELETE";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent != null
                && ACTION_NOTIFICATION_DELETE.equals(intent.getAction())
                && AudioService.instance != null) {
            AudioService.instance.handleDeleteNotification();
            return;
        }
        // 补丁:通知栏自定义动作(如收藏)的点击广播 → 直接派发到 onCustomAction
        if (intent != null
                && AudioService.CUSTOM_ACTION_BROADCAST.equals(intent.getAction())
                && AudioService.instance != null) {
            String name = intent.getStringExtra(AudioService.EXTRA_CUSTOM_ACTION_NAME);
            if (name != null) {
                AudioService.instance.dispatchCustomAction(name);
                return;
            }
        }
        // 补丁:通知栏按钮 / 耳机按键的 MEDIA_BUTTON 广播,直接派发给我们自己的
        // MediaSession 控制器,绕开 AndroidX MediaButtonReceiver 在 API>=26 时依赖
        // MediaSessionManager.getActiveSessions 的解析逻辑。部分 ROM(iQOO/MIUI/OriginOS)
        // 在暂停态下会把会话从「活跃会话列表」里剔除,导致 getActiveSessions 返回空、
        // onMediaButtonEvent 不被调用 → 暂停后点通知播放/暂停键「没反应」。
        // 我们自己的控制器永远连着本会话,直接 dispatch 即可稳定送达 onMediaButtonEvent,
        // 不再受 isActive / 系统活跃会话列表的影响。
        if (intent != null
                && Intent.ACTION_MEDIA_BUTTON.equals(intent.getAction())
                && AudioService.instance != null) {
            AudioService.instance.dispatchMediaButton(intent);
            return;
        }
        super.onReceive(context, intent);
    }
}
