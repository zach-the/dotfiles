#!/bin/bash
# Captive-portal auto-launch: NetworkManager already detects portal networks
# (nmcli general status -> CONNECTIVITY), but nothing on this system acts on
# that signal, so a WiFi network with a login page just sits at "no internet"
# until something makes an http:// request for the router to intercept.
# This polls that state and opens the browser the moment it flips to "portal".
PORTAL_URL="http://www.archlinux.org/check_network_status.txt"

prev=""
while true; do
    state=$(nmcli -t -f CONNECTIVITY general status 2>/dev/null)
    if [ "$state" = "portal" ] && [ "$prev" != "portal" ]; then
        xdg-open "$PORTAL_URL" &
    fi
    prev="$state"
    sleep 3
done
