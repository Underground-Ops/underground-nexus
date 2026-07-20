#!/bin/bash
# =============================================================================
#  fix-vault-audio-v2.sh — restore the FULL audio path to the Selkies stream
#  Cloud Underground · Underground Nexus · Nexus Creator Vault
#
#  WHAT v1 FIXED (kept here, now with skip/repair checks):
#    All Pulse clients → the Selkies PulseAudio server (/defaults/native);
#    ALSA→Pulse bridge; PipeWire/second-Pulse disabled; boot persistence.
#
#  WHAT v1 BROKE — THE SMOKING GUN THIS VERSION FIXES:
#    The Selkies service (svc-selkies) creates two NAMED null sinks at boot —
#    sink "output" (speakers) and sink "input" (mic) — guarded by the flag
#    file /dev/shm/audio.lock, and its capture leg records from
#    "output.monitor" BY NAME. v1 restarted PulseAudio, which destroyed those
#    runtime modules; the lock file still existed, so Selkies never recreated
#    them; Pulse auto-loaded the fallback "Dummy Output" (auto_null). Result:
#    pavucontrol shows meters moving on Dummy Output while the browser hears
#    nothing — audio playing into a sink nobody records. (Exactly the
#    screenshot symptom.)
#
#  WHAT v2 DOES (idempotent — every step prints SKIP / REPAIR / ADD):
#    1. Diagnose the whole chain.
#    2. v1 layers, with exists-checks: packages, client.conf.d, asound.conf,
#       autostart disables, competing daemons.
#    3. Ensure the /defaults Pulse server is up (restart ONLY if broken).
#    4. RECREATE the named sinks "output" + "input" if missing.
#    5. set-default-sink output; unmute; move every playing stream onto it.
#    6. Refresh /dev/shm/audio.lock and RESTART svc-selkies so its capture
#       reattaches to output.monitor.
#    7. VERIFY the capture: a recording client must appear on output.monitor.
#    8. Persist everything via /custom-cont-init.d (v2 script).
#    9. Test tone into sink "output".
#
#  BROWSER-SIDE (after this script):
#    hard-refresh the Selkies tab (Ctrl+Shift+R), toggle the sidebar speaker
#    icon ON, click once inside the desktop. All three matter.
#
#  Run as root:  docker exec -it nexus-creator-vault bash nexus-audio-driver-v4.sh
#
#  v3: adds s6-overlay persistence (matching the zero-trust-cockpit layer
#  pattern) so the routing config re-applies on every container restart, and
#  a container-only guard. The runtime repair itself is UNCHANGED from v2.
# =============================================================================

set -o pipefail
# ---------------------------------------------------------------- CONTAINER GUARD
# This driver is for CONTAINER webtops ONLY: the Nexus Creator Vault, the
# Workbench, and other linuxserver.io Selkies webtops. It is NOT for bare
# metal, VMs, or virtual appliances — those use normal system audio.
if [ ! -S /defaults/native ] && [ ! -d /run/service/svc-selkies ] && [ "$(readlink -f "$HOME" 2>/dev/null)" != "/config" ]; then
    echo "[audio-v4] ✗ No webtop container detected (no Selkies socket/service, HOME != /config)."
    echo "[audio-v4]   This driver only applies inside Nexus Creator Vault / Workbench-class"
    echo "[audio-v4]   containers. Bare metal and VMs use normal system audio — nothing to do."
    exit 1
fi

PULSE_DIR="/defaults"
PULSE_SOCK="${PULSE_DIR}/native"
LOCK="/dev/shm/audio.lock"
LOG="/tmp/nexus-audio-driver-v4.log"
say()  { echo "[audio-v4] $*"  | tee -a "$LOG"; }
ok()   { echo "[audio-v4] ✓ $*" | tee -a "$LOG"; }
skip() { echo "[audio-v4] ⏭ SKIP: $*" | tee -a "$LOG"; }
rep()  { echo "[audio-v4] 🔧 REPAIR: $*" | tee -a "$LOG"; }
warn() { echo "[audio-v4] ⚠ $*" | tee -a "$LOG"; }
fail() { echo "[audio-v4] ✗ $*" | tee -a "$LOG"; }

pactl_abc() { s6-setuidgid abc env PULSE_RUNTIME_PATH="${PULSE_DIR}" pactl "$@" 2>>"$LOG"; }

[ "$(id -u)" != "0" ] && { fail "run as root (docker exec -u 0)"; exit 1; }
: > "$LOG"

say "═══════════════════════════════════════════════════════════"
say " Nexus audio driver v4 — full-path restore + ORDERED s6 boot stage   $(date)"
say "═══════════════════════════════════════════════════════════"

# ---------------------------------------------------------------- 1. DIAGNOSE
say "STEP 1: Diagnosing..."
[ -S "$PULSE_SOCK" ] && ok "Pulse socket: $PULSE_SOCK" || warn "no Pulse socket yet"
[ -f "$LOCK" ] && say "audio.lock present (Selkies thinks sinks exist)" || say "audio.lock absent"
SINKS="$(pactl_abc list short sinks || true)"
say "current sinks:"; echo "$SINKS" | sed 's/^/[audio-v4]    /' | tee -a "$LOG"
echo "$SINKS" | grep -q "auto_null" && warn "auto_null (Dummy Output) present — the v1 failure signature"

# --------------------------------------------------- 2. v1 LAYERS, IDEMPOTENT
say "STEP 2: Base layers (packages, client routing, ALSA bridge, daemons)..."
NEED=""
command -v pulseaudio >/dev/null || NEED="$NEED pulseaudio"
command -v pactl      >/dev/null || NEED="$NEED pulseaudio-utils"
command -v amixer     >/dev/null || NEED="$NEED alsa-utils"
dpkg -s libasound2-plugins >/dev/null 2>&1 || dpkg -s libasound2-plugins:amd64 >/dev/null 2>&1 || NEED="$NEED libasound2-plugins"
command -v pavucontrol >/dev/null || NEED="$NEED pavucontrol"
if [ -n "$NEED" ]; then
    rep "installing:$NEED"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >>"$LOG" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $NEED >>"$LOG" 2>&1 && ok "installed" || warn "apt issues — see $LOG"
else
    skip "packages already present"
fi

CLIENTCONF="/etc/pulse/client.conf.d/99-selkies.conf"
if [ -f "$CLIENTCONF" ] && grep -q "default-server = unix:${PULSE_SOCK}" "$CLIENTCONF"; then
    skip "client routing already points at ${PULSE_SOCK}"
else
    rep "writing $CLIENTCONF"
    mkdir -p /etc/pulse/client.conf.d
    printf 'default-server = unix:%s\nautospawn = no\n' "$PULSE_SOCK" > "$CLIENTCONF"
fi

if [ -f /etc/asound.conf ] && grep -q "type pulse" /etc/asound.conf; then
    skip "ALSA→Pulse bridge already in place"
else
    rep "writing /etc/asound.conf"
    printf 'pcm.!default { type pulse }\nctl.!default { type pulse }\n' > /etc/asound.conf
fi

DIS=0
mkdir -p /config/.config/autostart
for f in pipewire pipewire-pulse wireplumber pipewire-media-session pulseaudio; do
    if [ -f "/etc/xdg/autostart/${f}.desktop" ] && [ ! -f "/config/.config/autostart/${f}.desktop" ]; then
        printf '[Desktop Entry]\nType=Application\nName=%s (disabled by audio-fix)\nHidden=true\n' "$f" \
            > "/config/.config/autostart/${f}.desktop"
        DIS=$((DIS+1))
    fi
done
chown -R abc:abc /config/.config/autostart 2>/dev/null
[ "$DIS" -gt 0 ] && rep "disabled $DIS autostart entries" || skip "competing autostarts already disabled"
pkill -f wireplumber 2>/dev/null; pkill -f pipewire-pulse 2>/dev/null; pkill -x pipewire 2>/dev/null
for pid in $(pgrep -x pulseaudio); do
    if ! tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -q "PULSE_RUNTIME_PATH=${PULSE_DIR}"; then
        rep "killing stray pulseaudio pid $pid (wrong runtime path)"
        kill "$pid" 2>/dev/null
    fi
done

# ------------------------------------------------ 3. PULSE SERVER (NO-RESTART)
say "STEP 3: Pulse server health (restart only if actually broken)..."
if pactl_abc info >/dev/null 2>&1; then
    skip "Pulse at ${PULSE_DIR} answers — NOT restarting (restarts are what killed the sinks)"
else
    rep "Pulse not answering — (re)starting"
    if [ -d /run/service/svc-pulseaudio ]; then
        s6-svc -r /run/service/svc-pulseaudio 2>>"$LOG"
    else
        s6-setuidgid abc env PULSE_RUNTIME_PATH="${PULSE_DIR}" HOME=/config \
            pulseaudio --exit-idle-time=-1 --daemonize=yes >>"$LOG" 2>&1
    fi
    for i in $(seq 1 20); do pactl_abc info >/dev/null 2>&1 && break; sleep 0.5; done
    pactl_abc info >/dev/null 2>&1 && ok "Pulse up" || { fail "Pulse would not come up — see $LOG"; exit 1; }
fi

# --------------------------------------- 4. THE NAMED SINKS SELKIES CAPTURES
say "STEP 4: Restoring the named sinks Selkies expects (output, input)..."
SINKS="$(pactl_abc list short sinks || true)"
if echo "$SINKS" | grep -qw "output"; then
    skip 'sink "output" already exists'
else
    rep 'creating null sink "output" (the sink Selkies records from)'
    pactl_abc load-module module-null-sink sink_name=output 'sink_properties=device.description="output"' >/dev/null \
        && ok 'sink "output" created' || fail 'could not create sink "output"'
fi
if echo "$SINKS" | grep -qw "input"; then
    skip 'sink "input" already exists'
else
    rep 'creating null sink "input" (mic path)'
    pactl_abc load-module module-null-sink sink_name=input 'sink_properties=device.description="input"' >/dev/null \
        && ok 'sink "input" created' || warn 'could not create sink "input" (mic only — not fatal for games)'
fi

# --------------------------------------------------- 5. DEFAULT + REROUTING
say "STEP 5: Default sink → output; unmute; move live streams..."
pactl_abc set-default-sink output && ok "default sink = output"
pactl_abc set-sink-mute output 0; pactl_abc set-sink-volume output 100%
MOVED=0
pactl_abc list short sink-inputs | awk '{print $1}' | while read -r si; do
    [ -n "$si" ] && pactl_abc move-sink-input "$si" output && say "  moved stream $si → output"
done
ok "sink output ready (unmuted, 100%)"

# ------------------------------------------- 6. REATTACH THE SELKIES CAPTURE
say "STEP 6: Restarting svc-selkies so its capture reattaches to output.monitor..."
touch "$LOCK"   # sinks exist now; keep Selkies' own creation block satisfied
if [ -d /run/service/svc-selkies ]; then
    s6-svc -r /run/service/svc-selkies 2>>"$LOG" && ok "svc-selkies restarted"
else
    warn "no /run/service/svc-selkies — custom image? try: s6-rc -a list | grep -i selkies"
fi

# ----------------------------------------------------------- 7. VERIFY CAPTURE
say "STEP 7: Verifying the capture leg (this is the definitive check)..."
ATTACHED=""
for i in $(seq 1 30); do
    if pactl_abc list source-outputs | grep -q "output.monitor"; then ATTACHED=yes; break; fi
    sleep 1
done
if [ -n "$ATTACHED" ]; then
    ok "CAPTURE ATTACHED — a client is recording from output.monitor. Server path is COMPLETE."
else
    warn "no recorder on output.monitor yet. This usually attaches when the browser"
    warn "session (re)subscribes: hard-refresh the Selkies tab, toggle the sidebar"
    warn "speaker ON, click the desktop once — then re-check with:"
    warn "  s6-setuidgid abc env PULSE_RUNTIME_PATH=${PULSE_DIR} pactl list source-outputs"
fi

# ------------------------------------------------------------- 8. PERSISTENCE
say "STEP 8: Persistence (v2 boot script)..."
mkdir -p /custom-cont-init.d 2>/dev/null
cat > /custom-cont-init.d/95-selkies-audio.sh << 'PERSIST'
#!/bin/bash
# Auto-generated by fix-vault-audio-v2.sh — reapplies audio routing at boot.
# NOTE: sinks "output"/"input" are created by svc-selkies itself at boot
# (audio.lock is cleared with /dev/shm on container restart), so this script
# only maintains client routing and keeps competitors out of the way.
mkdir -p /etc/pulse/client.conf.d
printf 'default-server = unix:/defaults/native\nautospawn = no\n' > /etc/pulse/client.conf.d/99-selkies.conf
printf 'pcm.!default { type pulse }\nctl.!default { type pulse }\n' > /etc/asound.conf
mkdir -p /config/.config/autostart
for f in pipewire pipewire-pulse wireplumber pipewire-media-session pulseaudio; do
    if [ -f "/etc/xdg/autostart/${f}.desktop" ]; then
        printf '[Desktop Entry]\nType=Application\nName=%s (disabled)\nHidden=true\n' "$f" \
            > "/config/.config/autostart/${f}.desktop"
    fi
done
chown -R abc:abc /config/.config/autostart 2>/dev/null
exit 0
PERSIST
chmod +x /custom-cont-init.d/95-selkies-audio.sh && ok "cont-init boot script installed"

# s6-overlay oneshot — registered in the user bundle exactly like the
# zero-trust-cockpit Dockerfile registers its services. Survives container
# RESTARTS; to survive container re-creation, bake the snippet printed at
# the end into the image.
S6=/etc/s6-overlay/s6-rc.d
if [ -d /etc/s6-overlay ]; then
    mkdir -p "$S6/nexus-audio-routing/dependencies.d"
    echo oneshot > "$S6/nexus-audio-routing/type"
    # v4 boot stage: config layer + AFTER-selkies default-sink selection.
    # Cold-boot root cause: selkies creates both null sinks, but Pulse's
    # fallback ("default") sink lands on the LAST-loaded sink = "input",
    # so every app plays into the mic sink and the stream captures silence.
    # Ordered after svc-selkies (real s6 dependency), wait for the server,
    # then set defaults BY NAME before any app starts. No selkies restart
    # at boot — its capture starts fresh after the sinks exist.
    cat > "$S6/nexus-audio-routing/script.sh" << 'BOOTS6'
#!/bin/bash
# nexus-audio-routing (s6 oneshot, after svc-selkies) — v4
bash /custom-cont-init.d/95-selkies-audio.sh 2>/dev/null || true
PULSE_DIR=/defaults
pa() { s6-setuidgid abc env PULSE_RUNTIME_PATH="$PULSE_DIR" pactl "$@" 2>/dev/null; }
for i in $(seq 1 40); do
    [ -S "$PULSE_DIR/native" ] && pa info >/dev/null 2>&1 && break
    sleep 0.5
done
if pa info >/dev/null 2>&1; then
    pa list short sinks | grep -q "^[0-9]*[[:space:]]output[[:space:]]" ||         pa load-module module-null-sink sink_name=output 'sink_properties=device.description="output"' >/dev/null
    pa list short sinks | grep -q "^[0-9]*[[:space:]]input[[:space:]]" ||         pa load-module module-null-sink sink_name=input 'sink_properties=device.description="input"' >/dev/null
    pa set-default-sink output
    pa set-default-source output.monitor
    pa set-sink-mute output 0
    pa set-sink-volume output 100%
    echo "[nexus-audio-routing] boot defaults set: sink=output source=output.monitor"
else
    echo "[nexus-audio-routing] pulse never answered at $PULSE_DIR — config layer only"
fi
exit 0
BOOTS6
    printf 'bash /etc/s6-overlay/s6-rc.d/nexus-audio-routing/script.sh\n' > "$S6/nexus-audio-routing/up"
    touch "$S6/nexus-audio-routing/dependencies.d/base"
    if [ -d /run/service/svc-selkies ] || [ -d "$S6/svc-selkies" ]; then
        touch "$S6/nexus-audio-routing/dependencies.d/svc-selkies"
        ok "ordered AFTER svc-selkies (real s6 dependency)"
    else
        warn "svc-selkies unit not visible — oneshot will rely on its own wait loop"
    fi
    mkdir -p "$S6/user/contents.d"
    touch "$S6/user/contents.d/nexus-audio-routing"
    chmod +x "$S6/nexus-audio-routing/script.sh"
    ok "s6-overlay oneshot 'nexus-audio-routing' v4 registered in the user bundle"
else
    warn "/etc/s6-overlay not present — skipping s6 registration"
fi

# --------------------------------------------------------------- 9. TEST TONE
say "STEP 9: Test tone into sink output (browser: speaker toggle ON + one click first)..."
python3 - << 'PY' 2>>"$LOG"
import math, struct, wave
w = wave.open('/tmp/selkies-test.wav', 'w')
w.setnchannels(2); w.setsampwidth(2); w.setframerate(44100)
for i in range(44100 * 2):
    v = int(12000 * math.sin(2 * math.pi * 440 * i / 44100))
    w.writeframes(struct.pack('<hh', v, v))
w.close()
PY
if s6-setuidgid abc env PULSE_RUNTIME_PATH="${PULSE_DIR}" paplay --device=output /tmp/selkies-test.wav 2>>"$LOG"; then
    ok "tone played into sink output"
else
    warn "paplay to sink output failed — see $LOG"
fi

say "═══════════════════════════════════════════════════════════"
say "DONE. Now, in the Selkies browser tab (localhost:1050):"
say "  1. HARD refresh the tab (Ctrl+Shift+R) — the WebRTC audio track"
say "     renegotiates per session."
say "  2. Sidebar speaker icon → ON."
say "  3. Click once inside the desktop (autoplay gesture)."
say "  4. In pavucontrol you should now see sink \"output\" (NOT Dummy Output)"
say "     under Output Devices, and Playback streams targeting it."

say "─────────────────────────────────────────────────────────────"
say "PERMANENT BAKE (survives container re-creation): add this layer to the"
say "zero-trust-cockpit Dockerfile, after LAYER 4:"
say ""
say "  RUN mkdir -p /etc/s6-overlay/s6-rc.d/nexus-audio-routing/dependencies.d \\"
say "      && echo oneshot > /etc/s6-overlay/s6-rc.d/nexus-audio-routing/type \\"
say "      && printf 'bash /etc/s6-overlay/s6-rc.d/nexus-audio-routing/script.sh\\n' > /etc/s6-overlay/s6-rc.d/nexus-audio-routing/up \\"
say "      && touch /etc/s6-overlay/s6-rc.d/nexus-audio-routing/dependencies.d/base \\"
say "      && touch /etc/s6-overlay/s6-rc.d/user/contents.d/nexus-audio-routing"
say "  (and COPY/write script.sh — the routing script this installer placed at"
say "   /custom-cont-init.d/95-selkies-audio.sh)"
say "Re-running this script is safe: existing pieces SKIP, broken pieces REPAIR."