_ORIGIN_PWD=$(pwd)
mkdir -p ./workdir
cd ./workdir
_SCRIPT_DIR="$(pwd -P)"

# ============================================================================
# System Detection
# ============================================================================

detect_os() {
    local os
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$os" in
        darwin) echo "macos" ;;
        linux)  echo "linux" ;;
        *)      echo "$os" ;;
    esac
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)        echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)             echo "$arch" ;;
    esac
}

detect_nproc() {
    local os="$1"
    if [ "$os" = "macos" ]; then
        sysctl -n hw.ncpu
    else
        nproc
    fi
}

_OS=$(detect_os)
_ARCH=$(detect_arch)
_NPROCESSORS=$(detect_nproc "$_OS")
export _OS
export _ARCH
export _NPROCESSORS

echo "CPU cores:                ${_NPROCESSORS}"
echo "Detected OS:              ${_OS}"
echo "Detected Architecture:    ${_ARCH}"
echo ""

