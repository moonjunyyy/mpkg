#!/bin/zsh
# Bootstrap development environment
# Installs: jq, openssl, curl, git, ruby, lua, node, rust, uv, oh-my-zsh, neovim, starship

# set -euo pipefail

# ============================================================================
# Initial Setup
# ============================================================================

ORIGINAL_PWD=$(pwd)
mkdir -p ./workdir
cd ./workdir
SCRIPT_DIR="$(pwd -P)"

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
        x86_64)         echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        *)              echo "$arch" ;;
    esac
}

detect_nproc() {
    local os="$1"
    if [[ "$os" == "macos" ]]; then
        sysctl -n hw.ncpu
    else
        nproc
    fi
}

export _OS=$(detect_os)
export _ARCH=$(detect_arch)
export _NPROCESSORS=$(detect_nproc $_OS)

echo "CPU cores:                ${_NPROCESSORS}"
echo "Detected _OS:             ${_OS}"
echo "Detected Architecture:    ${_ARCH}"
echo ""

# ============================================================================
# Environment Setup
# ============================================================================
PREFIX="${HOME}/.local"
export PREFIX

# Create directory structure
mkdir -p "${PREFIX}"/{bin,lib,include,share,soft,ssl}

# Export environment variables
export PATH="${PREFIX}/bin:${HOME}/.cargo/bin:${PATH}"
export CPATH="${PREFIX}/include${CPATH:+:${CPATH}}"
export CXXPATH="${PREFIX}/include${CXXPATH:+:${CXXPATH}}"
export LIBRARY_PATH="${PREFIX}/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"
export LD_LIBRARY_PATH="${PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export MANPATH="${PREFIX}/share/man:/usr/local/man${MANPATH:+:${MANPATH}}"

INSTALLATION_PATH="${PREFIX}/soft"
export INSTALLATION_PATH

echo "Installation prefix:      ${PREFIX}"
echo "Package directory:        ${INSTALLATION_PATH}"
echo ""

# ============================================================================
# Utility Functions
# ============================================================================

download_url() {
    local url="$1"
    local output="$2"
    
    echo "  → Downloading: $(basename "$output")"
    
    if command -v curl &>/dev/null; then
        curl -fsSL -o "${output}" "${url}" 2>&1 | grep -v "^$" || true
    elif command -v wget &>/dev/null; then
        wget -q -O "${output}" "${url}"
    else
        echo "Error: neither curl nor wget is available" >&2
        return 1
    fi
}

extract_version() {
    local pattern="$1"
    local file="$2"
    grep -oE "$pattern" "$file" | sort -Vr | head -n1
}

link_package() {
    local package_name="$1"
    local pkg_path="${INSTALLATION_PATH}/${package_name}"
    
    [[ -d "$pkg_path" ]] || {
        echo "Error: package directory not found: $pkg_path" >&2
        return 1
    }
    
    echo "  → Linking package: ${package_name}"
    
    # Iterate over directories (bin, lib, include, share, etc.)
    for dir in "${pkg_path}"/*; do
        [[ -d "$dir" ]] || continue
        local dir_name
        dir_name=$(basename "$dir")
        
        # Iterate over contents
        for item in "${dir}"/*; do
            [[ -e "$item" ]] || continue
            local item_name
            item_name=$(basename "$item")
            
            # Special handling for nested directories
            if [[ "$dir_name" == "share" && "$item_name" == "man" ]] || \
               [[ "$dir_name" == "lib" && "$item_name" == "pkgconfig" ]]; then
                # Create parent directory
                mkdir -p "${PREFIX}/${dir_name}/${item_name}"
                
                # Link each file inside
                for child in "${item}"/*; do
                    [[ -e "$child" ]] || continue
                    local child_name
                    child_name=$(basename "$child")
                    local target="${PREFIX}/${dir_name}/${item_name}/${child_name}"
                    
                    rm -f "$target"
                    ln -sf "${child}" "$target"
                done
            else
                # Direct linking for files and other directories
                mkdir -p "${PREFIX}/${dir_name}"
                local target="${PREFIX}/${dir_name}/${item_name}"
                
                rm -f "$target"
                ln -sf "${item}" "$target"
            fi
        done
    done
}

unlink_package() {
    local package_name="$1"
    local pkg_path="${INSTALLATION_PATH}/${package_name}"
    
    [[ -d "$pkg_path" ]] || {
        echo "Warning: package directory not found: $pkg_path" >&2
        return 0
    }
    
    echo "  → Unlinking package: ${package_name}"
    
    for dir in "${pkg_path}"/*; do
        [[ -d "$dir" ]] || continue
        local dir_name
        dir_name=$(basename "$dir")
        
        for item in "${dir}"/*; do
            [[ -e "$item" ]] || continue
            local item_name
            item_name=$(basename "$item")
            
            if [[ "$dir_name" == "share" && "$item_name" == "man" ]] || \
               [[ "$dir_name" == "lib" && "$item_name" == "pkgconfig" ]]; then
                for child in "${item}"/*; do
                    [[ -e "$child" ]] || continue
                    local child_name
                    child_name=$(basename "$child")
                    rm -f "${PREFIX}/${dir_name}/${item_name}/${child_name}"
                done
            else
                rm -f "${PREFIX}/${dir_name}/${item_name}"
            fi
        done
    done
}

get_installed_version() {
    local command="$1"
    local pattern="$2"
    
    if ! command -v "$command" &>/dev/null; then
        echo "0.0.0"
        return
    fi
    
    local output
    output=$("$command" --version 2>/dev/null || "$command" -v 2>/dev/null || echo "")
    
    if [[ "$output" =~ $pattern ]]; then
        echo "${match[1]}"
    else
        echo "0.0.0"
    fi
}

normalize_version() {
    echo "$1" | sed 's/[^0-9.]//g'
}

# ============================================================================
# Package Installation Functions
# ============================================================================

install_jq() {
    echo "=== Installing jq ==="
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    local installed_version
    installed_version=$(get_installed_version "jq" 'jq-([0-9]+\.[0-9]+\.[0-9]+)')
    echo "  Current version: ${installed_version}"
    
    download_url "https://github.com/jqlang/jq/tags" "jq_tags.html" || return 1
    local latest_tag
    latest_tag=$(extract_version 'jq-[0-9]+\.[0-9]+\.[0-9]+' "jq_tags.html")
    local latest_version="${latest_tag#jq-}"
    echo "  Latest version: ${latest_version}"
    
    if [[ "${latest_version}" == "${installed_version}" ]]; then
        echo "  ✓ Already up to date"
        echo ""
        rm -f jq_tags.html
        return 0
    fi
    
    local url="https://github.com/jqlang/jq/releases/download/jq-${latest_version}/jq-${_OS}-${_ARCH}"
    download_url "${url}" "jq-${_OS}-${_ARCH}" || return 1
    
    mkdir -p "${INSTALLATION_PATH}/${latest_tag}/bin"
    chmod +x "jq-${_OS}-${_ARCH}"
    mv "jq-${_OS}-${_ARCH}" "${INSTALLATION_PATH}/${latest_tag}/bin/jq"
    
    link_package "${latest_tag}"
    
    rm -f jq_tags.html
    echo "  ✓ Installed: ${latest_version}"
    echo ""
}

install_openssl() {
    echo "=== Installing OpenSSL ==="
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    local installed_version
    installed_version=$(get_installed_version "openssl" 'OpenSSL ([0-9]+\.[0-9]+\.[0-9]+)')
    echo "  Current version: ${installed_version}"
    
    download_url "https://github.com/openssl/openssl/tags" "openssl_tags.html" || return 1
    local latest_tag
    latest_tag=$(extract_version 'openssl-[0-9]+\.[0-9]+\.[0-9]+' "openssl_tags.html")
    local latest_version="${latest_tag#openssl-}"
    echo "  Latest version: ${latest_version}"
    
    if [[ "${latest_version}" == "${installed_version}" ]]; then
        echo "  ✓ Already up to date"
        echo ""
        rm -f openssl_tags.html
        return 0
    fi
    
    local url="https://github.com/openssl/openssl/releases/download/${latest_tag}/${latest_tag}.tar.gz"
    download_url "${url}" "${latest_tag}.tar.gz" || return 1
    
    echo "  → Extracting..."
    tar -xzf "${latest_tag}.tar.gz"
    
    mkdir -p "${INSTALLATION_PATH}/${latest_tag}"
    mkdir -p objdir
    cd objdir || return 1
    
    echo "  → Configuring..."
    "../${latest_tag}/Configure" \
        --prefix="${INSTALLATION_PATH}/${latest_tag}" \
        --openssldir="${PREFIX}/ssl" \
        >/dev/null 2>&1
    
    echo "  → Building (this may take a while)..."
    make -j"${_NPROCESSORS}" >/dev/null 2>&1
    
    echo "  → Installing..."
    make install_sw install_ssldirs >/dev/null 2>&1
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    link_package "${latest_tag}"
    
    rm -rf objdir "${latest_tag}" "${latest_tag}.tar.gz" openssl_tags.html
    echo "  ✓ Installed: ${latest_version}"
    echo ""
}

install_curl() {
    echo "=== Installing cURL ==="
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    local installed_version
    installed_version=$(get_installed_version "curl" 'curl ([0-9]+\.[0-9]+\.[0-9]+)')
    echo "  Current version: ${installed_version}"
    
    download_url "https://github.com/curl/curl/tags" "curl_tags.html" || return 1
    local latest_tag
    latest_tag=$(extract_version 'curl-[0-9]+_[0-9]+_[0-9]+' "curl_tags.html")
    local latest_version
    latest_version=$(echo "${latest_tag#curl-}" | tr '_' '.')
    echo "  Latest version: ${latest_version}"
    
    local installed_normalized
    installed_normalized=$(echo "$installed_version" | tr '.' '_')
    if [[ "${latest_tag}" == "curl-${installed_normalized}" ]]; then
        echo "  ✓ Already up to date"
        echo ""
        rm -f curl_tags.html
        return 0
    fi
    
    local url="https://github.com/curl/curl/releases/download/${latest_tag}/curl-${latest_version}.tar.gz"
    download_url "${url}" "curl-${latest_version}.tar.gz" || return 1
    
    echo "  → Extracting..."
    tar -xzf "curl-${latest_version}.tar.gz"
    
    mkdir -p "${INSTALLATION_PATH}/curl-${latest_version}"
    mkdir -p objdir
    cd objdir || return 1
    
    echo "  → Configuring..."
    "../curl-${latest_version}/configure" \
        --prefix="${INSTALLATION_PATH}/curl-${latest_version}" \
        --without-libpsl \
        --with-openssl="${PREFIX}" \
        >/dev/null 2>&1
    
    echo "  → Building..."
    make -j"${_NPROCESSORS}" >/dev/null 2>&1
    
    echo "  → Installing..."
    make install >/dev/null 2>&1
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    link_package "curl-${latest_version}"
    
    rm -rf objdir "curl-${latest_version}" "${latest_version}.tar.gz" curl_tags.html
    echo "  ✓ Installed: ${latest_version}"
    echo ""
}

install_git() {
    echo "=== Installing Git ==="
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    local installed_version
    installed_version=$(get_installed_version "git" 'git version ([0-9]+\.[0-9]+\.[0-9]+)')
    echo "  Current version: ${installed_version}"
    
    download_url "https://mirrors.edge.kernel.org/pub/software/scm/git/" "git_listing.html" || return 1
    local latest_tag
    latest_tag=$(extract_version 'git-[0-9]+\.[0-9]+\.[0-9]+' "git_listing.html")
    local latest_version="${latest_tag#git-}"
    echo "  Latest version: ${latest_version}"
    
    if [[ "${latest_version}" == "${installed_version}" ]]; then
        echo "  ✓ Already up to date"
        echo ""
        rm -f git_listing.html
        return 0
    fi
    
    local url="https://mirrors.edge.kernel.org/pub/software/scm/git/${latest_tag}.tar.gz"
    download_url "${url}" "${latest_tag}.tar.gz" || return 1
    
    echo "  → Extracting..."
    tar -xzf "${latest_tag}.tar.gz"
    
    mkdir -p "${INSTALLATION_PATH}/${latest_tag}"
    cd ${latest_tag} || return 1
    
    echo "  → Configuring..."
    ./configure --prefix="${INSTALLATION_PATH}/${latest_tag}" >/dev/null 2>&1
    
    echo "  → Building..."
    make -j"${_NPROCESSORS}" >/dev/null 2>&1
    
    echo "  → Installing..."
    make install >/dev/null 2>&1
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    link_package "${latest_tag}"
    
    rm -rf objdir "${latest_tag}" "${latest_tag}.tar.gz" git_listing.html
    echo "  ✓ Installed: ${latest_version}"
    echo ""
}

install_ruby() {
    echo "=== Installing Ruby ==="
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    local installed_version
    installed_version=$(get_installed_version "ruby" 'ruby ([0-9]+\.[0-9]+\.[0-9]+)')
    echo "  Current version: ${installed_version}"
    
    download_url "https://cache.ruby-lang.org/pub/ruby/" "ruby_listing.html" || return 1
    
    # Get major.minor versions
    local major_minor_versions
    major_minor_versions=($(grep -oE '[0-9]+\.[0-9]+/' "ruby_listing.html" | sort -Vr | uniq))
    
    local latest_version=""
    for ver in "${major_minor_versions[@]}"; do
        download_url "https://cache.ruby-lang.org/pub/ruby/${ver}" "ruby_patch_listing.html" || continue
        local patch_version
        patch_version=$(extract_version "ruby-${ver//\//}\.[0-9]+\.tar\.gz" "ruby_patch_listing.html")
        if [[ -n "$patch_version" ]]; then
            latest_version=$(echo "$patch_version" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
            rm -f ruby_patch_listing.html
            break
        fi
        rm -f ruby_patch_listing.html
    done
    
    echo "  Latest version: ${latest_version}"
    
    if [[ "${latest_version}" == "${installed_version}" ]]; then
        echo "  ✓ Already up to date"
        echo ""
        rm -f ruby_listing.html
        return 0
    fi
    
    local major_minor
    major_minor=$(echo "$latest_version" | grep -oE '[0-9]+\.[0-9]+')
    local url="https://cache.ruby-lang.org/pub/ruby/${major_minor}/ruby-${latest_version}.tar.gz"
    download_url "${url}" "ruby-${latest_version}.tar.gz" || return 1
    
    echo "  → Extracting..."
    tar -xzf "ruby-${latest_version}.tar.gz"
    
    mkdir -p "${INSTALLATION_PATH}/ruby-${latest_version}"
    mkdir -p objdir
    cd objdir || return 1
    
    echo "  → Configuring..."
    "../ruby-${latest_version}/configure" \
        --prefix="${INSTALLATION_PATH}/ruby-${latest_version}" \
        --disable-install-doc \
   	--enable-load-relative \
  	--enable-devel \
  	--enable-shared \
        >/dev/null 2>&1
    echo "  → Building..."
    make -j"${_NPROCESSORS}" >/dev/null 2>&1
    
    echo "  → Installing..."
    make install >/dev/null 2>&1
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    link_package "ruby-${latest_version}"
    
    rm -rf objdir "ruby-${latest_version}" "ruby-${latest_version}.tar.gz" ruby_listing.html
    echo "  ✓ Installed: ${latest_version}"
    echo ""
}

install_lua() {
    echo "=== Installing Lua ==="
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    local installed_version
    installed_version=$(get_installed_version "lua" 'Lua ([0-9]+\.[0-9]+\.[0-9]+)')
    echo "  Current version: ${installed_version}"
    
    download_url "https://www.lua.org/ftp/" "lua_listing.html" || return 1
    local latest_tag
    latest_tag=$(extract_version 'lua-[0-9]+\.[0-9]+\.[0-9]+' "lua_listing.html")
    local latest_version="${latest_tag#lua-}"
    echo "  Latest version: ${latest_version}"
    
    if [[ "${latest_version}" == "${installed_version}" ]]; then
        echo "  ✓ Already up to date"
        echo ""
        rm -f lua_listing.html
        return 0
    fi
    
    local url="https://www.lua.org/ftp/${latest_tag}.tar.gz"
    download_url "${url}" "${latest_tag}.tar.gz" || return 1
    
    echo "  → Extracting..."
    tar -xzf "${latest_tag}.tar.gz"
    
    cd "${latest_tag}" || return 1
    
    echo "  → Building..."
    if [[ "$_OS" == "macos" ]]; then
        make -j"${_NPROCESSORS}" macosx \
            MYCFLAGS="-fPIC" \
            INSTALL_TOP="${INSTALLATION_PATH}/${latest_tag}" \
            >/dev/null 2>&1
    else
        make -j"${_NPROCESSORS}" linux \
            MYCFLAGS="-fPIC" \
            INSTALL_TOP="${INSTALLATION_PATH}/${latest_tag}" \
            >/dev/null 2>&1
    fi
    
    echo "  → Installing..."
    make INSTALL_TOP="${INSTALLATION_PATH}/${latest_tag}" install >/dev/null 2>&1
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    link_package "${latest_tag}"
    
    rm -rf "${latest_tag}" "${latest_tag}.tar.gz" lua_listing.html
    echo "  ✓ Installed: ${latest_version}"
    echo ""
}

install_luarocks() {
    echo "=== Installing LuaRocks ==="
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    local installed_version
    installed_version=$(get_installed_version "luarocks" '[0-9]+\.[0-9]+\.[0-9]+')
    echo "  Current version: ${installed_version}"
    
    download_url "https://luarocks.org/releases/" "luarocks_listing.html" || return 1
    local latest_tag
    latest_tag=$(extract_version 'luarocks-[0-9]+\.[0-9]+\.[0-9]+' "luarocks_listing.html")
    local latest_version="${latest_tag#lua-}"
    echo "  Latest version: ${latest_version}"
    
    if [[ "${latest_version}" == "${installed_version}" ]]; then
        echo "  ✓ Already up to date"
        echo ""
        rm -f luarocks_listing.html
        return 0
    fi
    
    local url="https://luarocks.org/releases/${latest_tag}.tar.gz"
    download_url "${url}" "${latest_tag}.tar.gz" || return 1
    
    echo "  → Extracting..."
    tar -xzf "${latest_tag}.tar.gz"
    
    cd "${latest_tag}" || return 1
    
    echo "  → Configuring..."
    ./configure \
        --prefix="${INSTALLATION_PATH}/${latest_tag}" \
        >/dev/null 2>&1
    echo "  → Building..."
    make -j"${_NPROCESSORS}" >/dev/null 2>&1
    echo "  → Installing..."
    make INSTALL_TOP="${INSTALLATION_PATH}/${latest_tag}" install >/dev/null 2>&1
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    link_package "${latest_tag}"

    # Clean up
    rm -rf "${latest_tag}" "${latest_tag}.tar.gz" lua_listing.html
    echo "  ✓ Installed: ${latest_version}"
    echo ""
}

install_nodejs() {
    echo "=== Installing Node.js ==="
    
    if command -v node &>/dev/null; then
        echo "  ✓ Node.js is already installed: $(node --version)"
        echo ""
        return 0
    fi
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    echo "  → Installing NVM..."
    download_url "https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh" "install_nvm.sh" || return 1
    bash install_nvm.sh >/dev/null 2>&1
    
    export NVM_DIR="${HOME}/.nvm"
    [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"
    
    echo "  → Installing Node.js LTS..."
    nvm install --lts >/dev/null 2>&1
    nvm use --lts >/dev/null 2>&1
    
    rm -f install_nvm.sh
    echo "  ✓ Installed: $(node --version)"
    echo ""
}

install_rust() {
    echo "=== Installing Rust ==="
    
    if command -v cargo &>/dev/null; then
        echo "  ✓ Rust is already installed: $(rustc --version)"
        echo ""
        return 0
    fi
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    echo "  → Installing Rustup..."
    download_url "https://sh.rustup.rs" "install_rustup.sh" || return 1
    bash install_rustup.sh -y --no-modify-path >/dev/null 2>&1
    
    source "${HOME}/.cargo/env"
    
    rm -f install_rustup.sh
    echo "  ✓ Installed: $(rustc --version)"
    echo ""
}

install_uv() {
    echo "=== Installing uv (Python package manager) ==="
    
    if command -v uv &>/dev/null; then
        echo "  ✓ uv is already installed"
        echo ""
        return 0
    fi
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    echo "  → Installing uv..."
    download_url "https://astral.sh/uv/install.sh" "install_uv.sh" || return 1
    bash install_uv.sh >/dev/null 2>&1
    
    rm -f install_uv.sh
    
    echo "  → Installing Python..."
    uv python install >/dev/null 2>&1 || true
    
    echo "  ✓ Installed"
    echo ""
}

install_ohmyzsh() {
    echo "=== Installing Oh My Zsh ==="
    
    local ZSH_DIR="${HOME}/.oh-my-zsh"
    
    if [[ -d "$ZSH_DIR" ]]; then
        echo "  ✓ Oh My Zsh is already installed"
        echo ""
        return 0
    fi
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    echo "  → Installing Oh My Zsh..."
    download_url "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" "install_ohmyzsh.sh" || return 1
    RUNZSH=no bash install_ohmyzsh.sh --unattended >/dev/null 2>&1
    
    echo "  → Installing plugins..."
    git clone https://github.com/zsh-users/zsh-autosuggestions --depth=1 \
        "${ZSH_DIR}/custom/plugins/zsh-autosuggestions" >/dev/null 2>&1
    git clone https://github.com/zsh-users/zsh-syntax-highlighting --depth=1 \
        "${ZSH_DIR}/custom/plugins/zsh-syntax-highlighting" >/dev/null 2>&1
    
    rm -f install_ohmyzsh.sh
    echo "  ✓ Installed"
    echo ""
}

install_neovim() {
    echo "=== Installing Neovim ==="
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    local installed_version
    if command -v nvim &>/dev/null; then
        local version_output
        version_output=$(nvim --version 2>/dev/null | head -n1)
        if [[ "$version_output" =~ NVIM\ v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            installed_version="${match[1]}"
        else
            installed_version="0.0.0"
        fi
    else
        installed_version="0.0.0"
    fi
    echo "  Current version: ${installed_version}"
    
    # Need jq for this
    if ! command -v jq &>/dev/null; then
        echo "  ✗ jq is required but not installed"
        return 1
    fi
    
    download_url "https://api.github.com/repos/neovim/neovim/releases" "nvim_releases.json" || return 1
    
    local latest_version
    latest_version=$(jq -r '.[].tag_name' nvim_releases.json | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -Vr | head -n1)
    latest_version="${latest_version#v}"
    echo "  Latest version: ${latest_version}"
    
    if [[ "${latest_version}" == "${installed_version}" ]]; then
        echo "  ✓ Already up to date"
        rm -f nvim_releases.json
        return 0
    fi
    
    local asset_name="nvim-${_OS}-${_ARCH}.tar.gz"
    local url
    url=$(jq -r --arg ver "v${latest_version}" --arg name "$asset_name" \
        '.[] | select(.tag_name == $ver) | .assets[] | select(.name == $name) | .browser_download_url' \
        nvim_releases.json)
    
    if [[ -z "$url" ]]; then
        echo "  ✗ Could not find download URL for ${asset_name}"
        rm -f nvim_releases.json
        return 1
    fi
    
    download_url "${url}" "nvim-${latest_version}.tar.gz" || return 1
    
    echo "  → Extracting..."
    tar -xzf "nvim-${latest_version}.tar.gz"
    
    mkdir -p "${INSTALLATION_PATH}/nvim-${latest_version}"
    mv "nvim-${_OS}-${_ARCH}"/* "${INSTALLATION_PATH}/nvim-${latest_version}/"
    
    link_package "nvim-${latest_version}"
    
    # Setup basic vim config
    echo "  → Setting up configuration..."
    mkdir -p "${HOME}/.config/nvim/autoload"
    rm -rf "nvim-${_OS}-${_ARCH}" "nvim-${latest_version}.tar.gz" nvim_releases.json
    echo "  ✓ Installed: ${latest_version}"
    echo ""
}

install_neovim_config() {
    echo "=== Setting up Neovim Configuration ==="
    if [[ -d "${HOME}/.config/nvim" && -f "${HOME}/.config/nvim/init.vim" ]]; then
        echo "  → Neovim configuration already exists. Skipping."
        echo ""
        return 0
    fi  
    echo "  → Creating Neovim configuration..."
    mkdir -p "${HOME}/.config/nvim/autoload" || return 1
    cd "${HOME}/.config/nvim/" || return 1

    uv venv || return 1
    uv pip install neovim || return 1
    gem install neovim || return 1

    cat > "${HOME}/.config/nvim/init.vim" <<NVIM_CONFIG_EOF
source ~/.vimrc
lua << EOF
vim.fn.execute(vim.fn.stdpath('config') .. '.venv/bin/activate')
EOF
set completeopt+=menuone,noselect,popup
let g:clipboard = 'osc52'
" Set Python 3 interpreter with system path; Not a virtual environment
" let g:python3_host_prog  = '/usr/bin/python'
"
" If you are on macos or other POSIX system, or want to change the directory
" of python executable, need to change the path: 
" let g:python3_host_prog  = '/opt/homebrew/bin/python3.14'

" let g:clang_library_path = '/usr/lib/llvm-20/lib/libclang.so'
" let g:node_host_prog = '~/.nvm/versions/node/*/bin/neovim-node-host'

source ~/.config/nvim/autoload/plug.vim
filetype off                  " required
call plug#begin()
Plug 'L3MON4D3/LuaSnip'
Plug 'nvim-lua/plenary.nvim'
Plug 'OXY2DEV/markview.nvim'
Plug 'nvim-tree/nvim-tree.lua'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'catppuccin/nvim'
Plug 'williamboman/mason.nvim'
Plug 'williamboman/mason-lspconfig.nvim'
Plug 'neovim/nvim-lspconfig'
" Plug 'hrsh7th/nvim-cmp'
" Plug 'hrsh7th/cmp-nvim-lsp'
" Plug 'saadparwaiz1/cmp_luasnip'
Plug 'nvim-lualine/lualine.nvim'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'nvim-telescope/telescope.nvim', { 'branch': '0.1.x' }
Plug 'preservim/tagbar'
Plug 'tpope/vim-fugitive'
Plug 'lewis6991/gitsigns.nvim'
" Plug 'vim-airline/vim-airline'
" Plug 'rip-rip/clang_complete'
Plug 'github/copilot.vim'
call plug#end()             " required
filetype plugin indent on   " required
syntax on
set termguicolors
colorscheme catppuccin-mocha

" lua scripts
lua << EOF
require('gitsigns').setup()
require('luasnip').setup{}
require('lualine').setup{ options = { theme = 'auto' } }

--- Nvim Tree
require('nvim-tree').setup {
  view = {
    width = 35,
    side = 'left',
    signcolumn = 'yes',
  },
  renderer = {
    highlight_git = true,
    indent_markers = { enable = true },
  },
  filters = {
    dotfiles = false,
  },
  actions = {
    open_file = { quit_on_open = false },
  }
}
vim.keymap.set('n', '<C-n>', ':NvimTreeToggle<CR>', { silent = true })

local presets = require('markview.presets');
require('markview').setup({
    markdown = {
        headings = presets.headings.slanted
    },
    preview = {
        icon_provider = 'devicons'
    }
})
EOF

lua << EOF
-- Setup lspconfig.
require('nvim-treesitter.configs').setup{
  ensure_installed = { 'c','cpp','python','cmake','make','bash','lua','json','powershell','vim','markdown' },
  highlight = { enable = true, additional_vim_regex_highlighting = false },
  indent = { enable = true },
}
EOF

lua << EOF
--- Setup LSP keymaps and settings based on server capabilities
vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('userLspConfigs', {}),
    callback = function(args)
        local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
        --- vim.print('LSP started for buffer ' .. args.buf .. ' with client ID ' .. args.data.client_id)
        --- vim.print('Client name: ' .. client.name)
        --- vim.print('Client capabilities: ' .. vim.inspect(client.server_capabilities))

        vim.keymap.set('n', '<leader>gd',       vim.lsp.buf.declaration,     {silent=true})
        vim.keymap.set('n', '<leader>gD',       vim.lsp.buf.definition,      {silent=true})
        vim.keymap.set('n', '<leader>gi',       vim.lsp.buf.implementation,  {silent=true})
        vim.keymap.set('n', '<leader>gr',       vim.lsp.buf.references,      {silent=true})
        vim.keymap.set('n', '<leader>g0',       vim.lsp.buf.document_symbol, {silent=true})
        vim.keymap.set('n', '<leader><leader>', vim.lsp.buf.hover,           {silent=true})
        vim.keymap.set('n', '<leader>tD',       vim.lsp.buf.type_definition, {silent=true})

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'typeHierARCHyProvider') then
            vim.keymap.set('n', '<leader>tP', function() vim.lsp.buf.typehierachy({kind='subtypes'})   end, {silent=true})
            vim.keymap.set('n', '<leader>tC', function() vim.lsp.buf.typehierachy({kind='supertypes'}) end, {silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'codeLensProvider') then
            vim.keymap.set('n', '<leader>lc', function() vim.lsp.codelens.clear  ({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.keymap.set('n', '<leader>ls', function() vim.lsp.codelens.display({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.nvim_create_autocmd({'BufEnter','CursorHold','InsertLeave'}, {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function() vim.lsp.codelens.refresh({ bufnr = 0 }) end
            })
            vim.keymap.set('n', '<leader>lr', function() vim.lsp.codelens.refresh({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.keymap.set('n', '<leader>lS', function() vim.lsp.codelens.save   ({bufnr=0, client_id=args.data.client_id}) end, {silent=true})
            vim.keymap.set('n', '<leader>lg', function() vim.lsp.codelens.get({bufnr=0}) end, {silent=true})
            vim.keymap.set('n', '<leader>lR', vim.lsp.codelens.run, {silent=true})
        end

        vim.diagnostic.config({
            virtual_text = {
                prefix = '●',
                spacing = 4,
            },
            float = {
                border = 'rounded',
                source = 'always',
                header = '',
                prefix = '',
            },
            signs = true,
            underline = true,
            update_in_insert = false,
            severity_sort = true,
        })
        vim.keymap.set('n', '<leader>ee',  vim.diagnostic.open_float,               {silent=true})
        vim.keymap.set('n', '<leader>e]', function() vim.diagnostic.jump({count =  1, float=true}) end, {silent=true})
        vim.keymap.set('n', '<leader>e[', function() vim.diagnostic.jump({count = -1, float=true}) end, {silent=true})
        vim.keymap.set('n', '<leader>el', function() vim.diagnostic.setqflist(); vim.cmd('copen') end,  {silent=true})

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'signatureHelpProvider') then
            vim.keymap.set('n', '<leader>hS',    vim.lsp.buf.signature_help, {silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'codeActionProvider') then
            vim.keymap.set('n', '<leader>hA',    vim.lsp.buf.code_action,    {silent=true})
        end
         
        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'renameProvider') then
            vim.keymap.set('n', '<F2>',          vim.lsp.buf.rename,         {silent=true})
        end
 
        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'WorkspaceSymbolOptions') then
            vim.keymap.set('n', '<leader>G0',    vim.lsp.buf.workspace_symbol,{silent=true})
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'inlayHintProvider') then
            vim.lsp.inlay_hint.enable(true)
        end

        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'completionProvider') then
            --- for _char=32,126 do
            ---     vim.list_extend( client.server_capabilities.completionProvider.triggerCharacters, { string.char(_char), } )
            --- end
            buffer = vim.api.nvim_get_current_buf(),
            vim.lsp.completion.enable(true, client.id, 0, {
                autotrigger = true,
                convert = function(item)
                    return { abbr = item.label:gsub('%b()', '') }
                end,
            })
        end
        
        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentFormattingProvider') then
            vim.keymap.set('n', '<leader>hA', function()
                    vim.lsp.buf.format({ bufnr = args.buf, id = client.id, timeout_ms = 1000 })
                end
                ,{silent=true})
            vim.api.nvim_create_autocmd('BufWritePre', {
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                buffer = args.buf,
                callback = function()
                    vim.lsp.buf.format({ bufnr = args.buf, id = client.id, timeout_ms = 1000 })
                end,
            })
        end
        
        if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentHighlightProvider') then
            vim.api.nvim_create_autocmd('CursorHold', {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function()
                    vim.lsp.buf.document_highlight()
                end
            })
            vim.api.nvim_create_autocmd('CursorHoldI', {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function()
                    vim.lsp.buf.document_highlight()
                end
            })
            vim.api.nvim_create_autocmd('CursorMoved', {
                buffer = args.buf,
                group = vim.api.nvim_create_augroup('userLspConfigs', {clear=false}),
                callback = function()
                    vim.lsp.buf.clear_references() 
                end
            })
        end
       
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'diagnosticProvider') then
        --- end
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'declarationProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'definitionProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'implementationProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'referencesProvider') then
        --- end
        --- 
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentSymbolProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'hoverProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'typeDefinitionProvider') then
        --- end

        --- These capabilities not used for now, but can be added later
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'inlineValueProvider') then
        --- end
        
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'selectionRangeProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentRangeFormattingProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentOnTypeFormattingProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.willCreate') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.didCreate') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.willRename') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.didRename') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.willDelete') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'workspace.fileOperations.didDelete') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'foldingRangeProvider') then
        --- end

        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'colorProvider') then
        --- end
        
        --- if vim.list_contains(vim.tbl_keys(client.server_capabilities), 'documentLinkProvider') then
        --- end
    end,
})

--- Mason
require('mason').setup()
require('mason-lspconfig').setup({
    ensure_installed = { 'clangd', 'pyright', 'bashls', 'lua_ls', 'jsonls', 'powershell_es', 'vimls', 'markdown_oxide'},
    automatic_enable = true
})
EOF

" == Telescope ==
nnoremap <silent> <leader>ff :Telescope find_files<CR>
nnoremap <silent> <leader>fg :Telescope live_grep<CR>
nnoremap <silent> <leader>fb :Telescope buffers<CR>
nnoremap <silent> <leader>fh :Telescope help_tags<CR>
nnoremap <silent> <leader>Ch :highlight clear<CR>

" === Tagbar ===
nnoremap <leader>tb :TagbarToggle<CR>
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#formatter = 'default'

" CUDA filetype settings
augroup cuda_ft
  autocmd!
  autocmd BufRead,BufNewFile *.cu,*.cuh set filetype=cuda
augroup END

" Markdown filetype settings
augroup markdown
  autocmd!
  autocmd BufRead,BufNewFile *.md setlocal filetype=markdown
augroup END
NVIM_CONFIG_EOF
    echo "  ✓ Neovim configuration created"
    echo "  → Creating Vim configuration..."
    cat > "${HOME}/.vimrc" <<EOF
set hlsearch
set encoding=utf8
set fileencodings=utf-8,euc-kr,cp949
set bs=indent,eol,start
set history=1000
set ruler
set nobackup
set title
set showmatch
set nowrap
set wmnu
set wildmenu
set wildmode=longest:full,full
set cursorline
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set clipboard+=unnamedplus
set nu
set nocompatible
EOF
    echo "  ✓ Vim configuration created" 
    echo ""
    echo "  → Installing vim-plug..."
    download_url "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" \
        "${HOME}/.config/nvim/autoload/plug.vim" || true
    
    echo "  → Installing vim-plug..."
    nvim +PlugInstall +qall >/dev/null 2>&1 || true
    echo "  ✓ Installed"
    echo ""
}

install_starship() {
    echo "=== Installing Starship ==="
    
    if command -v starship &>/dev/null; then
        echo "  ✓ Starship is already installed: $(starship --version)"
        echo ""
        return 0
    fi
    
    cd "${ORIGINAL_PWD}/workdir" || return 1
    
    echo "  → Installing Starship..."
    download_url "https://starship.rs/install.sh" "install_starship.sh" || return 1
    bash install_starship.sh --bin-dir "${PREFIX}/bin" -y >/dev/null 2>&1
    
    echo "  → Downloading theme..."
    mkdir -p "${HOME}/.config/starship"
    download_url "https://starship.rs/presets/toml/jetpack.toml" \
        "${HOME}/.config/starship/jetpack.toml" || true
    
    rm -f install_starship.sh
    echo "  ✓ Installed: $(starship --version)"
    echo ""
}

# ============================================================================
# Main Installation
# ============================================================================

main() {
    echo "========================================"
    echo "  Development Environment Bootstrap"
    echo "========================================"
    echo ""

    # Core utilities
    install_jq
    install_openssl
    install_curl
    install_git
    
    # Programming languages
    install_ruby
    install_lua
    install_luarocks
    install_nodejs
    install_rust
    install_uv
    
    # Shell and editor
    install_ohmyzsh
    install_neovim
    install_neovim_config
    install_starship
    
    # Cleanup
    cd "${ORIGINAL_PWD}" || true
    rm -rf "${ORIGINAL_PWD}/workdir"

    cat > ~/.zshrc <<EOF
export PATH="${PATH}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}"
export ZSH="${HOME}/.oh-my-zsh"
export ZSH_THEME="robbyrussell"
export plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source \${ZSH}/oh-my-zsh.sh

# Starship prompt
export STARSHIP_CONFIG="${HOME}/.config/starship/jetpack.toml"
eval "\$(starship init zsh)"

# Rust
source "${HOME}/.cargo/env"

# NVM
export NVM_DIR="${HOME}/.nvm"
[ -s "\${NVM_DIR}/nvm.sh" ] && source "\${NVM_DIR}/nvm.sh"
EOF

    echo "========================================"
    echo "  ✓ Installation Complete!"
    echo "========================================"
}

main "$@"
