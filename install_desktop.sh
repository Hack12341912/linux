#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this script as the desktop user, not root." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This installer requires apt-get (Ubuntu/Debian)." >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required to install system packages." >&2
  exit 1
fi

echo "Updating Ubuntu packages..."
sudo apt-get update

if [[ ! -t 0 ]]; then
  echo "The installer requires an interactive terminal for its setup choices." >&2
  exit 2
fi

while true; do
  read -r -p "Install optional KDE packages and upgrade existing packages? [y/N]: " install_extras
  case "$install_extras" in
    [Yy]|[Nn]|"")
      break
      ;;
    *)
      echo "Please answer y or n."
      ;;
  esac
done

echo "Installing KDE Plasma, TigerVNC, noVNC, websockify, PulseAudio, and Microsoft Edge..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  curl \
  dbus-x11 \
  gnupg \
  kde-plasma-desktop \
  novnc \
  pulseaudio \
  pulseaudio-utils \
  iproute2 \
  tigervnc-standalone-server \
  websockify

if [[ "$install_extras" =~ ^[Yy]$ ]]; then
  echo "Upgrading existing packages and installing additional KDE packages..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    kde-standard \
    kde-config-systemd \
    plasma-desktop \
    plasma-workspace \
    kwin-x11 \
    dolphin \
    konsole \
    ark \
    kde-spectacle \
    plasma-nm \
    plasma-pa \
    systemsettings
else
  echo "Skipping optional KDE packages and package upgrades."
fi

if ! command -v microsoft-edge-stable >/dev/null 2>&1; then
  echo "Adding the Microsoft Edge package repository..."
  sudo install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor \
    | sudo tee /etc/apt/keyrings/microsoft-edge.gpg >/dev/null
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main" \
    | sudo tee /etc/apt/sources.list.d/microsoft-edge.list >/dev/null
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y microsoft-edge-stable
fi

mkdir -p "$HOME/.vnc"
chmod 700 "$HOME/.vnc"

cat >"$HOME/.vnc/xstartup" <<'XSTARTUP'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=KDE
exec dbus-run-session startplasma-x11
XSTARTUP
chmod 700 "$HOME/.vnc/xstartup"

for command_name in dbus-run-session startplasma-x11 vncserver vncpasswd websockify pactl ss microsoft-edge-stable; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found after installation: $command_name" >&2
    exit 1
  fi
done

if [[ ! -d /usr/share/novnc || ! -f /usr/share/novnc/vnc.html ]]; then
  echo "The noVNC web files were not installed at /usr/share/novnc." >&2
  exit 1
fi

chmod +x "$(dirname "$0")/start_desktop.sh"

# Prompt 1: VNC always requires its own password. Reuse an existing one.
if [[ ! -s "$HOME/.vnc/passwd" ]] || ! grep -q '^SECURITY_TYPES=VncAuth$' "$HOME/.vnc/startup.conf" 2>/dev/null; then
  if [[ ! -t 0 ]]; then
    echo "VNC password setup requires an interactive terminal." >&2
    exit 2
  fi
  echo
  echo "Prompt 1 of 2: set the VNC password (up to 8 characters)."
  vncpasswd "$HOME/.vnc/passwd"
  chmod 600 "$HOME/.vnc/passwd"
  printf 'SECURITY_TYPES=VncAuth\n' >"$HOME/.vnc/startup.conf"
  chmod 600 "$HOME/.vnc/startup.conf"
else
  echo "Existing VNC password found; keeping it."
fi

# Prompt 2: only ask when the Linux/KDE account does not already have one.
account_password_state="$(passwd -S "$USER" 2>/dev/null | awk '{print $2}')"
if [[ "$account_password_state" == "P" || "$account_password_state" == "L" ]]; then
  echo "Existing Linux/KDE password found; keeping it."
else
  if [[ ! -t 0 ]]; then
    echo "KDE/Linux password setup requires an interactive terminal." >&2
    exit 2
  fi
  echo
  echo "Prompt 2 of 2: choose the KDE/Linux account password policy."
  echo "1) Use a password (recommended)"
  echo "2) Use no Linux/KDE password"
  read -r -p "Selection [1]: " kde_password_choice
  kde_password_choice="${kde_password_choice:-1}"
  case "$kde_password_choice" in
    1)
      passwd
      ;;
    2)
      sudo passwd -d "$USER"
      ;;
    *)
      echo "Invalid selection." >&2
      exit 1
      ;;
  esac
  touch "$HOME/.vnc/kde-password-configured"
  chmod 600 "$HOME/.vnc/kde-password-configured"
fi

echo
echo "Installation complete. Start the desktop with:"
echo "  ./start_desktop.sh"
echo "VNC connection: 127.0.0.1:5901"
echo "noVNC connection: http://localhost:6082/vnc.html"