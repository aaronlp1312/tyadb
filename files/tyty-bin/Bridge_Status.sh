#!/data/data/com.termux/files/usr/bin/bash
out="$(~/bin/tybridge-status)"
termux-toast -g top "$out"
termux-notification --id 1312 --title "Tybridge status" --content "$out" --on-delete clear
