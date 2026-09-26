mpkg_inherit ghcommon

MPKG_TITLE="lazygit"
MPKG_DESC="Terminal UI for git"
MPKG_HOMEPAGE="https://github.com/jesseduffield/lazygit"
MPKG_DEPENDS=(git)

MPKG_GITHUB_REPO="jesseduffield/lazygit"
# lazygit spells the architectures x86_64 and arm64.
MPKG_ASSET='lazygit_${version}_${_GOOS}_${_UARCH/aarch64/arm64}.tar.gz'
