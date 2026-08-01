#!/bin/bash
# Re-arm RTC alarm 6 hours from now. Harmless if already running.
/usr/sbin/rtcwake -m no -s 21600
