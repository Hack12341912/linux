#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this script as the desktop user, not root." >&2
  exit 1
fi

main() {

VNC_DISPLAY=:1
VNC_PORT=5901
NOVNC_PORT=6082
VNC_DIR="$HOME/.vnc"
CONFIG_FILE="$VNC_DIR/startup.conf"
LOG_DIR="$HOME/.local/state/kde-vnc"
mkdir -p "$VNC_DIR" "$LOG_DIR"
chmod 700 "$VNC_DIR"

if [[ ! -x "$VNC_DIR/xstartup" ]]; then
  echo "Missing $VNC_DIR/xstartup. Run ./install_desktop.sh first." >&2
  exit 1
fi

configure_passwords

source "$CONFIG_FILE"

for command_name in dbus-run-session startplasma-x11 vncserver websockify; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is not installed. Run ./install_desktop.sh first." >&2
    exit 1
  fi
done

if [[ ! -f /usr/share/novnc/vnc.html ]]; then
  echo "noVNC is not installed at /usr/share/novnc. Run ./install_desktop.sh first." >&2
  exit 1
fi

# Stop only this user's desktop processes and the VNC display we own.
vncserver -kill "$VNC_DISPLAY" >/dev/null 2>&1 || true
pkill -u "$(id -u)" -f "websockify.*${NOVNC_PORT}" >/dev/null 2>&1 || true
pkill -u "$(id -u)" -f "startplasma-x11|plasmashell|kwin_x11" >/dev/null 2>&1 || true
sleep 1

RUNTIME_DIR=/run/user/$(id -u)
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
if [[ ! -d "$RUNTIME_DIR" ]]; then
  sudo mkdir -p "$RUNTIME_DIR"
  sudo chown "$(id -u):$(id -g)" "$RUNTIME_DIR"
  chmod 700 "$RUNTIME_DIR"
fi

if command -v pulseaudio >/dev/null 2>&1; then
  pulseaudio --start >/dev/null 2>&1 || true
  if command -v pactl >/dev/null 2>&1 && ! pactl list short sinks | grep -q '^.*[[:space:]]codespace_sink[[:space:]]'; then
    pactl load-module module-null-sink sink_name=codespace_sink sink_properties=device.description=Codespace_Virtual_Sink >/dev/null || true
  fi
  pactl set-default-sink codespace_sink >/dev/null 2>&1 || true
fi

vnc_args=("$VNC_DISPLAY" -geometry 1280x720 -depth 24 -localhost yes -SecurityTypes VncAuth -xstartup "$VNC_DIR/xstartup")
if [[ "$SECURITY_TYPES" == "VncAuth" ]]; then
  vnc_args+=( -PasswordFile "$VNC_DIR/passwd" )
fi
vncserver "${vnc_args[@]}" >"$LOG_DIR/vncserver.log" 2>&1
for attempt in {1..10}; do
  if command -v ss >/dev/null 2>&1 && ss -ltn | grep -q ":$VNC_PORT "; then
    break
  fi
  sleep 1
done
if command -v ss >/dev/null 2>&1 && ! ss -ltn | grep -q ":$VNC_PORT "; then
  echo "VNC did not open port $VNC_PORT. See $LOG_DIR/vncserver.log." >&2
  exit 1
fi
nohup websockify --web=/usr/share/novnc "0.0.0.0:$NOVNC_PORT" "127.0.0.1:$VNC_PORT" >"$LOG_DIR/websockify.log" 2>&1 &

echo "KDE Plasma started. noVNC: http://localhost:$NOVNC_PORT/vnc.html"
echo "VNC authentication: enabled"

}

# Configure the VNC/noVNC and KDE passwords before the desktop is started.
configure_passwords() {
  if [[ ! -f "$CONFIG_FILE" ]] || ! grep -q '^SECURITY_TYPES=VncAuth$' "$CONFIG_FILE"; then
    if [[ ! -t 0 ]]; then
      echo "VNC password setup requires an interactive terminal." >&2
      echo "Run ./start_desktop.sh directly, then enter the VNC password when prompted." >&2
      exit 2
    fi
    echo "VNC/noVNC requires a password."
    echo "Set the VNC password (up to 8 characters):"
    vncpasswd "$VNC_DIR/passwd"
    chmod 600 "$VNC_DIR/passwd"
    printf 'SECURITY_TYPES=VncAuth\n' >"$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
  fi

  account_password_state="$(passwd -S "$USER" 2>/dev/null | awk '{print $2}')"
  if [[ "$account_password_state" == "NP" && ! -f "$HOME/.vnc/kde-password-configured" ]]; then
    if [[ ! -t 0 ]]; then
      echo "KDE password setup requires an interactive terminal." >&2
      echo "Run ./start_desktop.sh directly to choose a KDE password or leave it passwordless." >&2
      exit 2
    fi
    read -r -p "Set or change the KDE Linux-user password now? [y/N]: " set_kde_password
    if [[ "$set_kde_password" =~ ^[Yy]$ ]]; then
      passwd
    fi
    touch "$HOME/.vnc/kde-password-configured"
    chmod 600 "$HOME/.vnc/kde-password-configured"
  fi
}

main "$@"
