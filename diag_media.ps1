# 云韵音乐 —— 系统媒体通知诊断抓包脚本
#
# 用法:
#   1) 手机打开「开发者选项 -> USB 调试」用数据线连电脑;
#      或者「无线调试 -> 使用配对码配对」后在 PowerShell 执行:
#         adb pair 手机IP:配对端口
#         adb connect 手机IP:5555
#   2) 打开云韵音乐,播放一首歌,让通知栏里出现播放通知
#   3) 双击运行本脚本(右键 -> 使用 PowerShell 运行)
#   4) 脚本会在 diag\ 目录生成 3 个文件,把整个 diag 目录发我即可

$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot 'diag'
New-Item -ItemType Directory -Path $out -Force | Out-Null

Write-Host '== 1/4 检查设备 =='
$devices = adb devices
$devices
if (-not ($devices | Select-String -Pattern '^\S+\s+device$')) {
    Write-Host ''
    Write-Host '没有检测到手机。请确认:'
    Write-Host '  - 已开启 USB 调试,数据线已连,手机上点过「允许调试」'
    Write-Host '  - 或已执行 adb pair / adb connect 完成无线调试配对'
    Read-Host '按回车退出'
    exit 1
}

Write-Host '== 2/4 media_session =='
adb shell dumpsys media_session | Out-File -FilePath "$out\media_session.txt" -Encoding utf8

Write-Host '== 3/4 notification =='
adb shell dumpsys notification --noredact | Out-File -FilePath "$out\notification.txt" -Encoding utf8

Write-Host '== 4/4 logcat(仅过滤音频/媒体/通知) =='
adb logcat -d -v brief | Select-String -Pattern 'audio|media|notification|AudioService|MediaSession|just_audio' |
    Out-File -FilePath "$out\logcat_filtered.txt" -Encoding utf8

Write-Host ''
Write-Host "完成,输出目录: $out"
Start-Process explorer.exe $out
Read-Host '按回车退出'
