mpkg_inherit ghcommon

MPKG_TITLE="tree-sitter"
MPKG_DESC="Parser generator CLI; nvim-treesitter uses it to build parsers"
MPKG_HOMEPAGE="https://tree-sitter.github.io/"

MPKG_GITHUB_REPO="tree-sitter/tree-sitter"
# The platform spellings are linux/macos and x64/arm64.
MPKG_ASSET='tree-sitter-cli-${_OS}-${_ARCH/amd64/x64}.zip'
