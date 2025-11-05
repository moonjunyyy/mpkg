OS=$(uname -s | tr '[:upper:]' '[:lower:]')
if [[ "$OS" == "darwin" ]]; then
    OS="macos"
    NPROCESSORS=$(sysctl -n hw.ncpu)
else
    NPROCESSORS=$(nproc)
fi
echo "Detected OS: $OS"

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    ARCH="amd64"
elif [[ "$ARCH" == "aarch64" || "$arch" == "arm64" ]]; then
    ARCH="arm64"
fi
echo "Detected Architecture: $ARCH"
echo
export PREFIX="$(echo ~/.local)"
export BINDIR="$PREFIX/bin"
export LIBDIR="$PREFIX/lib"
export LIBEXECDIR="$PREFIX/libexec"
export INCLUDEDIR="$PREFIX/include"
export SHAREDIR="$PREFIX/share"
export MANDIR="$PREFIX/share/man"

mkdir -p "$PREFIX/bin"
mkdir -p "$PREFIX/lib"
mkdir -p "$PREFIX/include"
mkdir -p "$PREFIX/share"
mkdir -p "$PREFIX/soft"

export PATH=~/.local/bin:$PATH
export LD_LIBRARY_PATH=~/.local/lib:/usr/local/lib:$LD_LIBRARY_PATH
export MANPATH="/usr/local/man:~/.local/man"
CFLAGS+="-I~/.local/include"
CXXFLAGS+="-I~/.local/include"

function link_package() {
    local package_path="$1"
    for dir in $(ls "$package_path"); do
        for item in $(ls "$package_path/$dir"); do
            # Handle the manual pages directory
            if [[ "$dir" == "share" ]] && [[ "$item" == "man" ]]; then
                mkdir -p "$PREFIX/share/man"
                for man in $(ls $package_path/$dir/$item); do
                    local src="$package_path/$dir/$item/$man"
                    local dest="$PREFIX/$dir/$item/$man"
                    ln -sf "$src" "$dest"
                done
                continue
            fi
            # Create symlink for other files and directories
            mkdir -p "$PREFIX/$dir"
            src="$package_path/$dir/$item"
            dest="$PREFIX/$dir/$item"
            ln -sf "$src" "$dest"
        done
    done
}

function unlink_package() {
    local package_path="$1"
    for dir in $(ls $package_path); do
        for item in $(ls "$package_path/$dir"); do
            # Handle the manual pages directory
            if [[ "$dir" == "share" ]] && [[ "$item" == "man" ]]; then
                for man in $(ls $package_path/$dir/$item); do
                    local dest="$PREFIX/$dir/$item/$man"
                    if [[ -L "$dest" ]]; then
                        rm "$dest"
                    fi
                done
                continue
            fi
            # Remove symlink for other files and directories
            local dest="\$PREFIX/$dir/$item"
            if [[ -L "$dest" ]]; then
                rm "$dest"
            fi
        done
    done
}

function download_url() {
    local url="$1"
    local output="$2"
    echo "Downloading $url to $output..."
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$output" "$url" > /dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url" > /dev/null 2>&1 
    else
        echo "Error: Neither curl nor wget is installed." >&2
        exit 1
    fi
}

local git_version="00.00.00"
# Check if Git is installed, if not install it locally 
if [[ "$(git --version 2> /dev/null)" =~ ^git\ version\ ([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    git_version="${match[1]}"
    echo "Git is already installed. Version: $git_version"
fi
download_url https://mirrors.edge.kernel.org/pub/software/scm/git/ tmp.html
local version=$(cat tmp.html | grep -o 'git-[0-9]\+\.[0-9]\+\.[0-9]\+' | sort -V | tail -n 1)
if [[ "$version" == "git-$git_version" ]]; then
    echo "Git is up to date. Version: $git_version"
    rm -rf tmp.html
else
    local url="https://mirrors.edge.kernel.org/pub/software/scm/git/$version.tar.gz"
    download_url "$url" "$version.tar.gz"
    tar -xzf "$version.tar.gz"
    cd "$version"
    mkdir -p $PREFIX/soft/${version}
    mkdir -p $PREFIX/soft/${version}/bin
    mkdir -p $PREFIX/soft/${version}/lib
    mkdir -p $PREFIX/soft/${version}/include
    mkdir -p $PREFIX/soft/${version}/libexec
    mkdir -p $PREFIX/soft/${version}/share
    
    PREFIX=$PREFIX/soft/${version} make -j$NPROCESSORS all && \
        PREFIX=$PREFIX/soft/${version} make install && \
        cd ..
    rm -rf "${version}" "${version}.tar.gz" tmp.html
    link_package "$PREFIX/soft/${version}"
fi
echo
# Install JQ if not already installed
local jq_version="0.00.00"
if [[ "$(jq --version 2> /dev/null)" =~ ^jq-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    jq_version="${match[1]}"
    echo "JQ is already installed. Version: $jq_version"
fi
download_url https://github.com/jqlang/jq/tags tmp.html
local version=$(cat tmp.html | grep -o 'jq-[0-9]\+\.[0-9]\+\.[0-9]\+' | sort -V | tail -n 1)
if [[ "$version" == "jq-$jq_version" ]]; then
    echo "JQ is up to date. Version: $jq_version"
    rm -rf tmp.html
else
    local url="https://github.com/jqlang/jq/releases/download/$version/jq%2D$OS%2D$ARCH"
    echo $url
    download_url $url $version
    chmod +x "$version"
    mkdir -p $PREFIX/soft/${version}/bin
    mv "$version" $PREFIX/soft/${version}/bin/jq
    rm -rf tmp.html
    link_package "$PREFIX/soft/$version";
fi
echo
local ruby_version="0.00.00"
if [[ "$(ruby --version 2>/dev/null)" =~ ruby\ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    ruby_version="${match[1]}"
    echo "Ruby is already installed. Version: $ruby_version"
fi
download_url "https://cache.ruby-lang.org/pub/ruby/" "tmp.html"
local major_minor_versions=( $(cat tmp.html | grep -o '[0-9]\+\.[0-9]\+\/' | sort -r) )
local patchversion=""
for ver in ${major_minor_versions[@]}; do
    download_url "https://cache.ruby-lang.org/pub/ruby/${ver}" "tmp.html"
    local item="$(cat tmp.html | grep -o "ruby-${ver/\/}\.[0-9]\+\.tar\.gz" | sort -V | tail -n 1)"
    if [[ -n "$item" ]]; then local patchversion="${item}"; break; fi 
done
if [[ "$patchversion" == "ruby-${ruby_version}.tar.gz" ]]; then
    echo "Ruby is up to date. Version: $ruby_version"
    rm -rf tmp.html
else
    echo $version
    local url="https://cache.ruby-lang.org/pub/ruby/${ver}${patchversion}.tar.gz"
    echo $url
    download_url "$url" "ruby-${patchversion/\///}/${patchversion}.version.tar.gz"
    tar -xzf "$version.tar.gz"
    mkdir -p $(echo "$PREFIX/soft/$version")
    ./configure --prefix=$(echo "$PREFIX/soft/$version") --disable-install-docs && \
        make -j$NPROCESSORS && \
        make install && \
        cd ..
    rm -rf "$version" "$version.tar.gz" tmp.html
    link_package "$PREFIX/soft/$version"
fi
echo
# local perl_version="0.00.00"
# if [[ "$(perl --version 2> /dev/null)" =~ v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
#     perl_version="${match[1]}"
#     echo "Perl is already installed. Version: $perl_version"
# fi
# download_url "https://www.cpan.org/src/5.0/" "tmp.html"
# # Perl in odd versions, so get two last versions and pick the odd one
# local version=$(cat tmp.html | grep -o 'perl-[0-9]\+\.[0-9]*[24680]\+\.[0-9]\+.tar.gz' | sort -V | tail -n 1)
# if [[ "$version" == "perl-$perl_version.tar.gz" ]]; then
#     echo "Perl is up to date. Version: $perl_version"
#     rm -rf tmp.html
# else
#     local url="https://www.cpan.org/src/5.0/${version}"
#     download_url "${url}" "${version}"
#     tar -xzf "$version"
#     cd "${version/.tar.gz/}"
#     ./configure -des -Dprefix=$(echo "$PREFIX/soft/${version/.tar.gz/}") -Duseshrplib
#     mkdir -p $(echo "$PREFIX/soft/${version/.tar.gz/}")
#     make -j$NPROCESSORS && \
#         make install && \
#         cd ..
#     rm -rf "$version" "$version.tar.gz" tmp.html
#     link_package "$PREFIX/soft/${version/.tar.gz/}"
# fi

local lua_version="0.00.00"
if [[ "$(lua -v 2> /dev/null)" =~ Lua\ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    lua_version="${match[1]}"
    echo "Lua is already installed. Version: $lua_version"
fi
download_url "https://www.lua.org/ftp/" "tmp.html"
local version=$(cat tmp.html | grep -o 'lua-[0-9]\+\.[0-9]\+\.[0-9]\+' | sort -V | tail -n 1)
if [[ "$version" == "lua-$lua_version" ]]; then
    echo "Lua is up to date. Version: $lua_version"
    rm -rf tmp.html
else
    local url="https://www.lua.org/ftp/$version.tar.gz"
    echo $version
    echo $url
    download_url "$url" "$version.tar.gz"
    tar -xzf "$version.tar.gz"
    cd "$version"
    mkdir -p $(echo "$PREFIX/soft/$version")
    make -j$NPROCESSORS linux MYCFLAGS="-fPIC" INSTALL_TOP=$(echo "$PREFIX/soft/$version") && \
        make INSTALL_TOP=$(echo "$PREFIX/soft/$version") install && \
        cd ..
    rm -rf "$version" "$version.tar.gz" tmp.html
    link_package "$PREFIX/soft/$version"
fi

echo
which node 2> /dev/null
if [[ $? -eq 0 ]]; then
    echo "Node.js is already installed."
else
    download_url "https://raw.githubusercontent.com/creationix/nvm/master/install.sh" "install_nvm.sh"
    bash install_nvm.sh
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
    rm -rf install_nvm.sh
fi

echo
which cargo 2> /dev/null
if [[ $? -eq 0 ]]; then
    echo "Rust is already installed."
else
    download_url "https://sh.rustup.rs" "install_rustup.sh"
    bash install_rustup.sh -y --no-modify-path
    source $HOME/.cargo/env
    rm -rf install_rustup.sh
fi

echo
# Install uv if not already installed
which uv 2> /dev/null
if [[ $? -eq 0 ]]; then
    echo "uv is already installed."
else
    download_url "https://astral.sh/uv/install.sh" "install_uv.sh"
    bash install_uv.sh -a "$ARCH" -o "$OS" -p "$PREFIX"
    rm -rf install_uv.sh
    uv python install
fi

export ZSH="$HOME/.oh-my-zsh"
# Bootstrap Oh My Zsh and Starship if not already installed
if [[ ! -d $ZSH ]] then
    download_url 'https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh' 'install_ohmyzsh.sh'
    bash install_ohmyzsh.sh --unattended
    rm -rf install_ohmyzsh.sh

    # Zsh autosuggestions plugin and syntax highlighting
    git clone 'https://github.com/zsh-users/zsh-autosuggestions' --depth=1 $ZSH/custom/plugins/zsh-autosuggestions
    git clone 'https://github.com/zsh-users/zsh-syntax-highlighting' --depth=1 $ZSH/custom/plugins/zsh-syntax-highlighting
fi

echo
local nvim_version="0.00.00"
alias ll='ls -la'
if [[ "$(nvim --version 2> /dev/null)" =~ NVIM\ v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    nvim_version="${match[1]}"
    echo "Neovim is already installed. Version: $nvim_version"
else    
    local neovim_versions=$(download_url https://api.github.com/repOS/neovim/neovim/releases tmp.html)
    local version=$(jq -r '.[].tag_name' tmp.html | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1) 
    echo $version
    local url=$(jq -r --arg ver "$version" --arg OS "$os" --arg ARCH "$arch" '.[] | select(.tag_name == $ver) | .assets[] | select(.name == "nvim-" + $os + "-" + $arch + ".tar.gz") | .browser_download_url' tmp.html)
    echo $url
    download_url "$url" "nvim-$version.tar.gz"
    tar -xzf "nvim-$version.tar.gz"
    mv nvim-$OS-$ARCH $PREFIX/soft/nvim-$version
    rm -rf "nvim-$version.tar.gz" tmp.html
    link_package "$PREFIX/soft/nvim-$version"
    mkdir -p ~/.config/nvim/autoload
    cat > ~/.vimrc << EOF
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
set wildmenu | set wildmode=longest:full,full
set cursorline
set tabstop=4                                  
set shiftwidth=4
set softtabstop=4
set expandtab
set clipboard+=unnamedplus
set nu
set nocompatible
EOF
download_url "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" ~/.config/nvim/autoload/plug.vim
nvim --headless +PlugInstall +qall
fi

clear

export ZSH_THEME="robbyrussell"
export plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
)

export STARSHIP_THEME="jetpack"
export HIST_STAMPS="mm/dd/yyyy"
if [[ $(which starship &> /dev/null) -gt 0 ]] then
    download_url 'https://starship.rs/install.sh' 'install_starship.sh'
    bash install_starship.sh --bin-dir "$PREFIX/bin" -y
    rm -rf install_starship.sh
    download_url 'https://starship.rs/presets/toml/jetpack.toml' '~/.config/starship/jetpack.toml'
fi
export STARSHIP_CONFIG=~/.config/starship/$STARSHIP_THEME.toml

source $ZSH/oh-my-zsh.sh
eval "$(starship init zsh)"
