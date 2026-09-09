#!/bin/bash
# TyADB Installation Script for Termux
# Downloads dependencies, creates directories, sets permissions, and configures tyadb
# Usage: curl https://raw.githubusercontent.com/aaronlp1312/tyadb/main/install.sh | bash
#    or: bash install.sh (when running locally from repo)

set -euo pipefail

# ============================================================================
# Configuration & Logging
# ============================================================================

TYADB_INSTALLER_VERSION="2.0.0"
GITHUB_REPO="aaronlp1312/tyadb"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
GITHUB_BASE="https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  printf "${BLUE}[tyadb]${NC} %s\n" "$*"
}

log_success() {
  printf "${GREEN}[tyadb]${NC} ✓ %s\n" "$*"
}

log_warn() {
  printf "${YELLOW}[tyadb]${NC} ⚠ %s\n" "$*" >&2
}

log_error() {
  printf "${RED}[tyadb]${NC} ✗ %s\n" "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

# ============================================================================
# Environment Detection
# ============================================================================

check_termux() {
  if [ -z "${PREFIX:-}" ]; then
    die "Not running in Termux. Install Termux first: https://f-droid.org/packages/com.termux/"
  fi
  
  if [ "${PREFIX}" != "/data/data/com.termux/files/usr" ]; then
    die "Invalid Termux PREFIX: $PREFIX (expected /data/data/com.termux/files/usr)"
  fi
  
  log_success "Termux environment detected: $PREFIX"
}

detect_installation_mode() {
  # Check if running from local repo or downloading from GitHub
  if [ -f "$(dirname "$0")/files/tyadb" ] 2>/dev/null; then
    INSTALL_MODE="local"
    REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
    log_info "Local installation mode: using files from $REPO_ROOT"
  else
    INSTALL_MODE="remote"
    log_info "Remote installation mode: downloading from $GITHUB_BASE"
  fi
}

# ============================================================================
# Dependency Installation
# ============================================================================

install_dependencies() {
  log_info "Updating Termux package metadata..."
  if ! pkg update -y >/dev/null 2>&1; then
    die "Failed to update package metadata. Check internet connection."
  fi
  log_success "Package metadata updated"
  
  # Required packages
  local required_packages=(
    "android-tools"  # adb
    "bash"           # shell interpreter
    "coreutils"      # timeout, nohup, standard utilities
    "curl"           # HTTP health checks
    "gawk"           # awk parsing
    "grep"           # text search
    "sed"            # stream editing
  )
  
  # Recommended packages
  local recommended_packages=(
    "iproute2"       # ip command for network detection
    "netcat-openbsd" # nc for port testing
    "python"         # tyadb-control.py support
  )
  
  # Optional packages (non-fatal if they fail)
  local optional_packages=(
    "fzf"            # enhanced interactive menu
    "termux-api"     # wake lock and WiFi helpers
  )
  
  log_info "Installing required packages: ${required_packages[*]}"
  if ! pkg install -y "${required_packages[@]}" >/dev/null 2>&1; then
    die "Failed to install required packages"
  fi
  log_success "Required packages installed"
  
  log_info "Installing recommended packages: ${recommended_packages[*]}"
  if ! pkg install -y "${recommended_packages[@]}" >/dev/null 2>&1; then
    log_warn "Some recommended packages failed to install (non-critical)"
  else
    log_success "Recommended packages installed"
  fi
  
  log_info "Installing optional packages: ${optional_packages[*]}"
  if ! pkg install -y "${optional_packages[@]}" >/dev/null 2>&1; then
    log_warn "Optional packages not available (this is OK)"
  else
    log_success "Optional packages installed"
  fi
}

# ============================================================================
# Directory Structure Setup
# ============================================================================

create_directory_structure() {
  log_info "Creating directory structure..."
  
  # User-facing commands
  mkdir -p "$HOME/bin"
  
  # TyDroid internal structure
  mkdir -p "$HOME/tydroid/bin"
  mkdir -p "$HOME/tydroid/tyty/bin"
  mkdir -p "$HOME/tydroid/config"
  mkdir -p "$HOME/environments/tyty-droid"
  
  # State and config (XDG Base Directory spec)
  mkdir -p "$HOME/.config/tydroid/adb"
  mkdir -p "$HOME/.local/state/tydroid/adb"
  mkdir -p "$HOME/.local/state/tydroid/logs"
  
  # Legacy paths (for compatibility)
  mkdir -p "$HOME/.tydroid"
  
  log_success "Directory structure created"
}

# ============================================================================
# File Download & Installation (Remote Mode)
# ============================================================================

download_file() {
  local url="$1" dest="$2" filename
  filename=$(basename "$dest")
  
  log_info "Downloading $filename..."
  
  if ! curl -fsSL "$url" -o "$dest" 2>/dev/null; then
    die "Failed to download $filename from $url"
  fi
  
  if [ ! -s "$dest" ]; then
    die "Downloaded file is empty: $dest"
  fi
  
  log_success "Downloaded $filename"
}

download_files_remote() {
  log_info "Downloading tyadb files from GitHub..."
  
  # Main scripts
  download_file "$GITHUB_BASE/files/tyadb" "$HOME/bin/tyadb"
  download_file "$GITHUB_BASE/files/tyadb-boot" "$HOME/bin/tyadb-boot"
  download_file "$GITHUB_BASE/files/tyadb-control.py" "$HOME/bin/tyadb-control.py"
  download_file "$GITHUB_BASE/files/tyadb-modern.sh" "$HOME/bin/tyadb-modern.sh"
  
  # Compatibility shortcuts (these are tiny, safe to create locally)
  for cmd in auto connect devices doctor info mdns pair panel ping reconnect save-serial shell status tasker tcpip watch; do
    cat > "$HOME/bin/tyadb-$cmd" <<EOF
#!/bin/bash
exec tyadb $cmd "\$@"
EOF
  done
  
  log_success "Downloaded all tyadb files"
}

# ============================================================================
# File Installation (Local Mode)
# ============================================================================

install_files_local() {
  log_info "Installing tyadb files from local repository..."
  
  local payload="$REPO_ROOT/files"
  
  # Verify payload exists
  [ -f "$payload/tyadb" ] || die "Bundle incomplete: files/tyadb not found"
  [ -d "$payload/tyty-bin" ] || die "Bundle incomplete: files/tyty-bin not found"
  
  # Copy main scripts
  for src in "$payload"/*.sh "$payload"/tyadb*; do
    if [ -f "$src" ]; then
      local name
      name=$(basename "$src")
      cp -f "$src" "$HOME/bin/$name"
      log_success "Installed $name"
    fi
  done
  
  # Copy tyty-bin layer if it exists
  if [ -d "$payload/tyty-bin" ] && [ "$(find "$payload/tyty-bin" -type f | wc -l)" -gt 0 ]; then
    log_info "Installing TyDroid command layer..."
    for src in "$payload/tyty-bin"/*; do
      if [ -f "$src" ]; then
        local name
        name=$(basename "$src")
        cp -f "$src" "$HOME/tydroid/tyty/bin/$name"
        chmod 700 "$HOME/tydroid/tyty/bin/$name"
        ln -sf "$HOME/tydroid/tyty/bin/$name" "$HOME/bin/$name"
        log_success "Installed $name (with symlink)"
      fi
    done
  fi
}

# ============================================================================
# Permissions & Configuration
# ============================================================================

set_permissions() {
  log_info "Setting file permissions..."
  
  # Main executables
  chmod 755 "$HOME/bin"/tyadb* 2>/dev/null || true
  chmod 755 "$HOME/bin"/tyadb 2>/dev/null || die "Failed to set tyadb executable permission"
  
  # Python bridge if present
  if [ -f "$HOME/bin/tyadb-control.py" ]; then
    chmod 755 "$HOME/bin/tyadb-control.py"
    log_success "Set tyadb-control.py executable"
  fi
  
  # Config files (readable but not world-visible)
  chmod 600 "$HOME/.config/tydroid/adb"/* 2>/dev/null || true
  chmod 700 "$HOME/.local/state/tydroid/adb" 2>/dev/null || true
  chmod 700 "$HOME/.local/state/tydroid/logs" 2>/dev/null || true
  
  log_success "Permissions set"
}

install_config_files() {
  log_info "Installing configuration files..."
  
  local config_src
  if [ "$INSTALL_MODE" = "local" ]; then
    config_src="$REPO_ROOT/config"
  else
    # Create minimal config on-the-fly for remote install
    mkdir -p /tmp/tyadb-config-$$
    config_src="/tmp/tyadb-config-$$"
    
    # Download or create config templates
    cat > "$config_src/tyadb.env.example" <<'ENVEOF'
# TyADB environment configuration
TYDROID_ROOT="${TYDROID_ROOT:-${HOME}/tydroid}"
ADB_BIN="${TYADB_ADB_BIN:-$(command -v adb)}"
TYADB_DEFAULT_HOST="${TYADB_DEFAULT_HOST:-}"
TYADB_STATE_DIR="${HOME}/.local/state/tydroid/adb"
TYADB_CONFIG_DIR="${HOME}/.config/tydroid/adb"
TYADB_LOG_DIR="${HOME}/.local/state/tydroid/logs"
ENVEOF
    
    cat > "$config_src/tyty-adb.conf" <<'CONFEOF'
# TyDroid ADB configuration
# Bridge port for Tydroid core API
TYADB_BRIDGE_PORT=1313
# UI port
TYADB_UI_PORT=1312
# Optional: default wireless ADB host
# TYADB_DEFAULT_HOST=192.168.1.100:5555
CONFEOF
  fi
  
  # Copy config files
  if [ -f "$config_src/tyadb.env.example" ]; then
    cp -f "$config_src/tyadb.env.example" "$HOME/tydroid/config/tyadb.env" 2>/dev/null || true
    chmod 600 "$HOME/tydroid/config/tyadb.env"
    log_success "Installed tyadb.env"
  fi
  
  if [ -f "$config_src/tyty-adb.conf" ]; then
    cp -f "$config_src/tyty-adb.conf" "$HOME/tydroid/config/tyty-adb.conf" 2>/dev/null || true
    chmod 600 "$HOME/tydroid/config/tyty-adb.conf"
    log_success "Installed tyty-adb.conf"
  fi
  
  # Cleanup temp config if remote
  [ "$INSTALL_MODE" = "remote" ] && rm -rf /tmp/tyadb-config-$$
}

# ============================================================================
# PATH Configuration
# ============================================================================

configure_path() {
  log_info "Configuring PATH..."
  
  if [ -z "${PATH##*$HOME/bin*}" ]; then
    log_success "~/bin already in PATH"
    return 0
  fi
  
  # Add to ~/.bashrc (Termux default shell)
  if [ -f "$HOME/.bashrc" ]; then
    if ! grep -q 'export PATH.*HOME/bin' "$HOME/.bashrc"; then
      cat >> "$HOME/.bashrc" <<'BASHEOF'

# tyadb commands
export PATH="$HOME/bin:$PATH"
BASHEOF
      log_success "Added ~/bin to PATH in ~/.bashrc"
    fi
  fi
  
  # Add to ~/.profile as fallback
  if [ -f "$HOME/.profile" ]; then
    if ! grep -q 'export PATH.*HOME/bin' "$HOME/.profile"; then
      cat >> "$HOME/.profile" <<'PROFEOF'

# tyadb commands
export PATH="$HOME/bin:$PATH"
PROFEOF
      log_success "Added ~/bin to PATH in ~/.profile"
    fi
  fi
  
  # For current session
  export PATH="$HOME/bin:$PATH"
}

# ============================================================================
# Verification
# ============================================================================

verify_installation() {
  log_info "Verifying installation..."
  
  local errors=0
  
  # Check main binary
  if [ ! -x "$HOME/bin/tyadb" ]; then
    log_error "tyadb executable not found or not executable"
    errors=$((errors + 1))
  else
    log_success "tyadb executable OK"
  fi
  
  # Check key directories
  for dir in "$HOME/bin" "$HOME/.local/state/tydroid/adb" "$HOME/.config/tydroid/adb"; do
    if [ ! -d "$dir" ]; then
      log_error "Directory missing: $dir"
      errors=$((errors + 1))
    else
      log_success "Directory OK: $dir"
    fi
  done
  
  # Check ADB
  if ! command -v adb >/dev/null 2>&1; then
    log_error "adb not found in PATH"
    errors=$((errors + 1))
  else
    log_success "adb found: $(command -v adb)"
  fi
  
  if [ $errors -gt 0 ]; then
    die "Verification failed with $errors error(s)"
  fi
  
  log_success "Installation verified"
}

# ============================================================================
# Post-Installation
# ============================================================================

post_install_info() {
  cat <<'EOF'

╔════════════════════════════════════════════════════════════════╗
║          TyADB Installation Complete!                          ║
╚════════════════════════════════════════════════════════════════╝

Quick Start:
  1. Reload your shell:
       source ~/.bashrc

  2. Check setup:
       tyadb doctor

  3. Pair wireless ADB (from Android Settings > Developer Options):
       tyadb pair <HOST:PAIR_PORT> <6-DIGIT-CODE>

  4. Connect:
       tyadb connect <HOST:5555>

  5. Test connection:
       tyadb ping

Documentation:
  • Full command guide:  tyadb help
  • Troubleshooting:     tyadb doctor
  • Device info:         tyadb info
  • Watch connection:    tyadb watch start

Files:
  • Binaries:        $HOME/bin/tyadb*
  • Config:          $HOME/tydroid/config/
  • State:           $HOME/.local/state/tydroid/adb/
  • Logs:            $HOME/.local/state/tydroid/logs/

Next Steps:
  • Enable Wireless Debugging on your Android device
  • Run: tyadb doctor (to see full status)
  • Set up voice commands for your AI assistant

GitHub:
  https://github.com/aaronlp1312/tyadb

EOF
}

# ============================================================================
# Main Installation Flow
# ============================================================================

main() {
  log_info "TyADB Installer v$TYADB_INSTALLER_VERSION"
  
  # Check environment
  check_termux
  detect_installation_mode
  
  # Install
  install_dependencies
  create_directory_structure
  
  if [ "$INSTALL_MODE" = "remote" ]; then
    download_files_remote
  else
    install_files_local
  fi
  
  set_permissions
  install_config_files
  configure_path
  
  # Verify
  verify_installation
  
  # Success
  log_success "TyADB installed successfully!"
  post_install_info
}

# Run main installation
main "$@"
