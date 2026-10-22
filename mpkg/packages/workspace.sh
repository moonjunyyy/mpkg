# The whole development environment, as one target:  mpkg install workspace
# The solver derives the build order from each package's own dependencies,
# so there is no hand-maintained install sequence to keep in step.

mpkg_inherit metacommon

MPKG_TITLE="Workspace"
MPKG_DESC="Everything: toolchain, languages, editor, PDF viewer and shell"
MPKG_DEPENDS=(
    mpkg
    git
    ruby
    lua
    luarocks
    nodejs
    rust
    go
    uv
    neovim
    nvim-config
    mason
    zathura-pdf-poppler
    starship
    shell-config            # pulls in oh-my-zsh where zsh exists
)
