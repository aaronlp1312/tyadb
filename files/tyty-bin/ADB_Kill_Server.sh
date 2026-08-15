#!/data/data/com.termux/files/usr/bin/bash
adb kill-server || true
termux-toast -g top "adb server killed"
