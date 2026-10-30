# The plain-Vim settings in config/vim/vimrc, as ~/.vimrc. Neovim does not
# read it; its configuration is nvim-config.

mpkg_inherit configcommon

MPKG_TITLE="Vim configuration"
MPKG_DESC="~/.vimrc for plain vim (editing basics, UTF-8/EUC-KR, 4-space indent)"
MPKG_CONFIG_SRC='config/vim/vimrc'
MPKG_CONFIG_DEST='${HOME}/.vimrc'
