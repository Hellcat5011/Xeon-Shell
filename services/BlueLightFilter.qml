
import QtQuick
import Quickshell
import Quickshell.Io
import QtCore

Item {
    id: root
    
    property int currentKelvin: Config.blueLightDayTemp
    property int targetKelvin: Config.blueLightDayTemp
    property real currentLat: 0
    property real currentLon: 0

    // ── Time helpers ──

    // Validate a time string: must be "HH:MM" with 0≤HH≤23 and 0≤MM≤59.
    function isValidTimeStr(timeStr) {
        if (!timeStr || typeof timeStr !== "string") return false;
        let re = /^\d{1,2}:\d{2}$/;
        if (!re.test(timeStr.trim())) return false;
        let parts = timeStr.trim().split(":");
        let h = parseInt(parts[0], 10);
        let m = parseInt(parts[1], 10);
        if (isNaN(h) || isNaN(m)) return false;
        return h >= 0 && h <= 23 && m >= 0 && m <= 59;
    }

    // Parse "HH:MM" to minutes-since-midnight (0–1439).
    // Returns defaultMinutes on any invalid input.
    function parseTimeToMinutes(timeStr, defaultMinutes) {
        if (!isValidTimeStr(timeStr)) return defaultMinutes;
        let parts = timeStr.trim().split(":");
        let h = parseInt(parts[0], 10);
        let m = parseInt(parts[1], 10);
        return h * 60 + m;
    }

    // Is `nowMins` inside the night window [nightStart, nightEnd)?
    // The night window can wrap around midnight (e.g. 22:00 → 06:00).
    // If nightStart === nightEnd, the night window is empty (always day).
    function isNighttime(nowMins, nightStartMins, nightEndMins) {
        if (nightStartMins === nightEndMins) return false;
        if (nightStartMins < nightEndMins) {
            // Same-day window, e.g. 01:00 → 05:00
            return nowMins >= nightStartMins && nowMins < nightEndMins;
        } else {
            // Overnight window, e.g. 22:00 → 06:00
            return nowMins >= nightStartMins || nowMins < nightEndMins;
        }
    }

    // ── Interpolation engine ──
    //
    // The transition must END at the boundary time. With a duration D:
    //   - Night ramp: runs from (nightStart - D) to nightStart.
    //     At nightStart the night temperature is fully reached.
    //   - Day ramp: runs from (nightEnd - D) to nightEnd.
    //     At nightEnd the day temperature is fully reached.
    //
    // We compute the temperature purely from the current clock position.
    // This handles shell (re)starts mid-transition correctly — no trigger
    // needed, we just read the clock and derive the temperature.
    //
    // If the ramp duration is longer than the gap between the two boundaries
    // (i.e. the ramps would overlap), we clamp each ramp to half the gap so
    // they meet in the middle without crossing.

    // Signed distance in minutes from `from` to `to` on a 24-hour clock,
    // always in range (0, 1440]. Used to measure the gap between boundaries.
    function clockDistance(from, to) {
        let d = (to - from + 1440) % 1440;
        return d === 0 ? 1440 : d;
    }

    // Progress through a ramp window: returns 0.0 at rampStart, 1.0 at rampEnd.
    // rampStart/rampEnd in minutes (may be negative or >1440 before modding).
    // nowMins is current time (0–1439).
    // The window can wrap midnight.
    function rampProgress(nowMins, rampStartMins, rampEndMins, durationMins) {
        if (durationMins <= 0) return -1; // instant change, handled by caller

        // Normalise start/end into [0,1440)
        let start = ((rampStartMins % 1440) + 1440) % 1440;
        let end   = ((rampEndMins   % 1440) + 1440) % 1440;

        // Check whether nowMins is inside [start, end) on the circular clock.
        let inside;
        if (start < end) {
            inside = (nowMins >= start && nowMins < end);
        } else if (start > end) {
            inside = (nowMins >= start || nowMins < end);
        } else {
            // duration is a full day — treat as always inside
            inside = true;
        }

        if (!inside) return -1; // outside this ramp window

        // Linear progress within the window
        let elapsed = (nowMins - start + 1440) % 1440;
        return Math.min(1.0, elapsed / durationMins);
    }

    // Compute the target temperature from the current clock, taking into
    // account the two boundaries and the transition duration.
    function computeTemperatureFromTime(nowMins, nightStartMins, nightEndMins, transitionMins, dayTemp, nightTemp) {
        // If nightStart === nightEnd → no night window, always day
        if (nightStartMins === nightEndMins) return dayTemp;

        let dur = Math.max(0, transitionMins);

        // Clamp ramp duration if it would cause overlapping ramps.
        // Gap A = clockwise distance from nightEnd to nightStart (the day period).
        // Gap B = clockwise distance from nightStart to nightEnd (the night period).
        // The night-ramp (day→night) lives in gap A and ends at nightStart.
        // The day-ramp (night→day) lives in gap B and ends at nightEnd.
        let gapDay   = clockDistance(nightEndMins, nightStartMins);
        let gapNight = clockDistance(nightStartMins, nightEndMins);
        let nightRampDur = Math.min(dur, gapDay);
        let dayRampDur   = Math.min(dur, gapNight);

        // Night ramp: day→night, ends AT nightStart (runs from nightStart-dur to nightStart)
        let nightRampStart = nightStartMins - nightRampDur;
        let prog = rampProgress(nowMins, nightRampStart, nightStartMins, nightRampDur);
        if (prog >= 0) {
            // Interpolate day→night
            return Math.round(dayTemp + (nightTemp - dayTemp) * prog);
        }

        // Day ramp: night→day, ends AT nightEnd (runs from nightEnd-dur to nightEnd)
        let dayRampStart = nightEndMins - dayRampDur;
        prog = rampProgress(nowMins, dayRampStart, nightEndMins, dayRampDur);
        if (prog >= 0) {
            // Interpolate night→day
            return Math.round(nightTemp + (dayTemp - nightTemp) * prog);
        }

        // Outside both ramp windows → flat temperature
        if (isNighttime(nowMins, nightStartMins, nightEndMins)) {
            return nightTemp;
        } else {
            return dayTemp;
        }
    }

    function computeTarget() {
        if (!Config.blueLightEnabled) {
            return Config.blueLightDayTemp;
        }
        if (Config.blueLightManualOn) {
            return Config.blueLightNightTemp;
        }
        
        let now = new Date();
        let currentMins = now.getHours() * 60 + now.getMinutes() + (now.getSeconds() + now.getMilliseconds() / 1000.0) / 60.0;

        let dayTemp   = Config.blueLightDayTemp;
        let nightTemp = Config.blueLightNightTemp;
        let dur       = Config.blueLightTransitionMinutes;

        let isFixedTimeMode = (Config.blueLightMode === "fixed_time" || Config.blueLightMode === "time");

        if (isFixedTimeMode) {
            // Night-hours semantics: start = when night begins, end = when night ends
            let nightStart = parseTimeToMinutes(Config.blueLightNightStart, 22 * 60); // default 22:00
            let nightEnd   = parseTimeToMinutes(Config.blueLightNightEnd,    6 * 60); // default 06:00

            let result = computeTemperatureFromTime(currentMins, nightStart, nightEnd, dur, dayTemp, nightTemp);
            if (isNaN(result)) result = dayTemp;
            // Clamp to valid range
            let lo = Math.min(dayTemp, nightTemp);
            let hi = Math.max(dayTemp, nightTemp);
            return Math.max(lo, Math.min(hi, result));
        } else {
            // Sunset/Sunrise mode
            let lat = 0;
            let lon = 0;
            if (Config.blueLightUseIpLocation) {
                lat = currentLat;
                lon = currentLon;
            } else {
                lat = parseFloat(Config.blueLightLatitude);
                lon = parseFloat(Config.blueLightLongitude);
            }
            if (isNaN(lat) || isNaN(lon) || (lat === 0 && lon === 0)) {
                // Fallback: no valid coordinates. Use fixed-time defaults.
                console.warn("BlueLightFilter: invalid/missing coordinates, falling back to fixed defaults (22:00–06:00)");
                let nightStart = parseTimeToMinutes(Config.blueLightNightStart, 22 * 60);
                let nightEnd   = parseTimeToMinutes(Config.blueLightNightEnd,    6 * 60);
                let result = computeTemperatureFromTime(currentMins, nightStart, nightEnd, dur, dayTemp, nightTemp);
                if (isNaN(result)) result = dayTemp;
                let lo = Math.min(dayTemp, nightTemp);
                let hi = Math.max(dayTemp, nightTemp);
                return Math.max(lo, Math.min(hi, result));
            }
            
            // Solar position calculation (unchanged from original)
            let start = new Date(now.getFullYear(), 0, 0);
            let diff = now - start;
            let dayOfYear = Math.floor(diff / 86400000);
            
            let gamma = (2 * Math.PI / 365) * (dayOfYear - 1 + (now.getHours() - 12) / 24);
            let eqTime = 229.18 * (0.000075 + 0.001868 * Math.cos(gamma) - 0.032077 * Math.sin(gamma) - 0.014615 * Math.cos(2 * gamma) - 0.040849 * Math.sin(2 * gamma));
            let decl = 0.006918 - 0.399912 * Math.cos(gamma) + 0.070257 * Math.sin(gamma) - 0.006758 * Math.cos(2 * gamma) + 0.000907 * Math.sin(2 * gamma) - 0.002697 * Math.cos(3 * gamma) + 0.00148 * Math.sin(3 * gamma);
            
            let ha = Math.acos( Math.cos(90.833 * Math.PI / 180) / (Math.cos(lat * Math.PI / 180) * Math.cos(decl)) - Math.tan(lat * Math.PI / 180) * Math.tan(decl) );
            if (isNaN(ha)) ha = Math.PI / 2;
            
            let sunriseMins = 720 - 4 * (lon + ha * 180 / Math.PI) - eqTime;
            let sunsetMins = 720 - 4 * (lon - ha * 180 / Math.PI) - eqTime;
            
            let offsetMins = now.getTimezoneOffset();
            let localSunrise = ((sunriseMins - offsetMins) % 1440 + 1440) % 1440;
            let localSunset  = ((sunsetMins  - offsetMins) % 1440 + 1440) % 1440;

            // In sunset/sunrise mode: sunset = nightStart, sunrise = nightEnd.
            // The ramp toward night ends at sunset; the ramp toward day ends at sunrise.
            let result = computeTemperatureFromTime(currentMins, localSunset, localSunrise, dur, dayTemp, nightTemp);
            if (isNaN(result)) result = dayTemp;
            let lo = Math.min(dayTemp, nightTemp);
            let hi = Math.max(dayTemp, nightTemp);
            return Math.max(lo, Math.min(hi, result));
        }
    }

    function checkLocationProc() {
        if (Config.blueLightEnabled && 
            (Config.blueLightMode === "sunset_sunrise" || Config.blueLightMode === "realtime") && 
            Config.blueLightUseIpLocation) {
            locationProc.running = true;
        }
    }

    function sendTemperature(kelvin) {
        if (!gammaProcess.running) return;
        // Guard: never send NaN, negative, or unreasonable values
        if (isNaN(kelvin) || kelvin < 1000 || kelvin > 10000) {
            console.warn("BlueLightFilter: refusing to send invalid kelvin value:", kelvin);
            return;
        }
        let cmd = JSON.stringify({ type: "set_temperature", kelvin: kelvin });
        gammaProcess.write(cmd + "\n");
    }

    // ── Evaluation: purely time-derived, no step-based ramp ──
    // Every tick, recompute the correct temperature from the clock.
    // The step timer is only used when manualOn snaps instantly.

    Timer {
        id: stepTimer
        interval: 100
        repeat: true
        running: currentKelvin !== targetKelvin
        onTriggered: {
            if (currentKelvin === targetKelvin) {
                running = false;
                return;
            }
            
            // For instant changes (manual toggle), snap immediately
            currentKelvin = targetKelvin;
            sendTemperature(currentKelvin);
        }
    }

    // Periodic re-evaluation: recalculate from the clock every 2 seconds
    // (frequent enough for smooth ramps, light enough on CPU).
    Timer {
        id: evalTimer
        interval: 2000
        repeat: true
        running: Config.blueLightEnabled
        onTriggered: {
            let newTarget = computeTarget();
            if (newTarget !== currentKelvin) {
                targetKelvin = newTarget;
                currentKelvin = newTarget;
                sendTemperature(newTarget);
            }
        }
    }

    Connections {
        target: Config
        function onBlueLightEnabledChanged() {
            if (Config.blueLightEnabled) {
                if (!gammaProcess.running) {
                    gammaProcess.running = true;
                    targetKelvin = computeTarget();
                } else {
                    targetKelvin = computeTarget();
                    currentKelvin = targetKelvin;
                    sendTemperature(currentKelvin);
                }
                checkLocationProc();
            } else {
                targetKelvin = Config.blueLightDayTemp;
                currentKelvin = targetKelvin;
                sendTemperature(targetKelvin);
            }
        }
        function onBlueLightManualOnChanged() { 
            targetKelvin = computeTarget(); 
            currentKelvin = targetKelvin;
            sendTemperature(currentKelvin);
        }
        function onBlueLightModeChanged() { 
            checkLocationProc();
            targetKelvin = computeTarget();
            currentKelvin = targetKelvin;
            sendTemperature(currentKelvin);
        }
        function onBlueLightUseIpLocationChanged() {
            checkLocationProc();
            targetKelvin = computeTarget();
            currentKelvin = targetKelvin;
            sendTemperature(currentKelvin);
        }
        function onBlueLightNightStartChanged() {
            targetKelvin = computeTarget();
            currentKelvin = targetKelvin;
            sendTemperature(currentKelvin);
        }
        function onBlueLightNightEndChanged() {
            targetKelvin = computeTarget();
            currentKelvin = targetKelvin;
            sendTemperature(currentKelvin);
        }
        function onBlueLightTransitionMinutesChanged() {
            targetKelvin = computeTarget();
            currentKelvin = targetKelvin;
            sendTemperature(currentKelvin);
        }
        function onBlueLightLatitudeChanged() { targetKelvin = computeTarget(); currentKelvin = targetKelvin; sendTemperature(currentKelvin); }
        function onBlueLightLongitudeChanged() { targetKelvin = computeTarget(); currentKelvin = targetKelvin; sendTemperature(currentKelvin); }
        function onBlueLightDayTempChanged() { targetKelvin = computeTarget(); currentKelvin = targetKelvin; sendTemperature(currentKelvin); }
        function onBlueLightNightTempChanged() { targetKelvin = computeTarget(); currentKelvin = targetKelvin; sendTemperature(currentKelvin); }
    }

    Process {
        id: gammaProcess
        command: [Quickshell.shellDir + "/helpers/gamma-ctl/target/release/gamma-ctl"]
        stdinEnabled: true
        
        stdout: SplitParser {
            onRead: data => console.log("gamma-ctl:", data)
        }
        stderr: SplitParser {
            onRead: data => console.error("gamma-ctl error:", data)
        }
        
        onStarted: {
            currentKelvin = computeTarget();
            targetKelvin = currentKelvin;
            sendTemperature(currentKelvin);
        }

        onExited: (exitCode) => {
            console.warn("BlueLightFilter: gamma-ctl exited with code", exitCode);
            if (Config.blueLightEnabled) {
                console.log("BlueLightFilter: scheduling gamma-ctl auto-restart in 1s...");
                gammaRestartTimer.start();
            }
        }
    }

    Timer {
        id: gammaRestartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (Config.blueLightEnabled && !gammaProcess.running) {
                console.log("BlueLightFilter: auto-restarting gamma-ctl now");
                gammaProcess.running = true;
            }
        }
    }

    Process {
        id: locationProc
        command: ["python3", Quickshell.shellDir + "/scripts/get-location.py"]
        stdout: SplitParser {
            onRead: data => {
                let parts = data.trim().split(",");
                if (parts.length === 2) {
                    root.currentLat = parseFloat(parts[0]);
                    root.currentLon = parseFloat(parts[1]);
                    let newTarget = computeTarget();
                    root.targetKelvin = newTarget;
                    root.currentKelvin = newTarget;
                    sendTemperature(newTarget);
                }
            }
        }
    }

    Component.onCompleted: {
        if (Config.blueLightEnabled) {
            gammaProcess.running = true;
            checkLocationProc();
        }
    }
}
