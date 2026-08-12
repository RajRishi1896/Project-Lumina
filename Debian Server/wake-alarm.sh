#!/bin/bash
# Purpose: Re-arm the RTC wake alarm 6 hours from now so the laptop boots daily.
# Usage:   Called by wake-alarm.service after every boot (or run manually).
# Args:    None
# Idempotent: Yes -- re-arming the same alarm is harmless.
/usr/sbin/rtcwake -m no -s 21600
