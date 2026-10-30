mpkg_inherit srccommon

MPKG_TITLE="OpenSSL"
MPKG_DESC="TLS library and command line tool"
MPKG_HOMEPAGE="https://www.openssl.org/"
MPKG_PROBE_CMD="openssl"
MPKG_REQUIRES_CMD=(cc make perl)

MPKG_LISTING_URL="https://github.com/openssl/openssl/tags"
MPKG_TAG_PATTERN='openssl-[0-9]+\.[0-9]+\.[0-9]+'
MPKG_TARBALL_URL='https://github.com/openssl/openssl/releases/download/${tag}/${tag}.tar.gz'

# OpenSSL ships 'Configure' (capital C) and splits install into sw + ssldirs;
# a full `make install` would also build the manpages, which takes minutes.
MPKG_CONFIGURE="Configure"
MPKG_CONFIGURE_FLAGS=(
    --openssldir='${MPKG_PREFIX}/ssl'
    --libdir=lib          # keep everything in lib/, not a split lib64/
    shared
)
MPKG_INSTALL_TARGETS=(install_sw install_ssldirs)

# Headers are reached as <openssl/ssl.h> through ${MPKG_PREFIX}/include, which
# core.sh already puts on CPATH. Never add ${MPKG_PREFIX}/include/openssl
# itself: its trace.h, http.h, store.h ... then shadow same-named headers of
# whatever is built next (git's refs/debug.c picks up openssl/trace.h and fails
# with "'REFS' undeclared").

# install_ssldirs creates an *empty* ${MPKG_PREFIX}/ssl/certs. Everything later
# linked against this OpenSSL -- curl, git, ruby -- would then reject every
# certificate on the internet. Point its default CAfile/CApath at the system
# trust store so https works out of the box.
mpkg_post_install() {
    mkdir -p "${MPKG_PREFIX}/ssl/certs"
    if [[ -n "${MPKG_CA_BUNDLE}" ]]; then
        ln -sf "${MPKG_CA_BUNDLE}" "${MPKG_PREFIX}/ssl/cert.pem"
        mpkg::step "trust store: ${MPKG_CA_BUNDLE}"
    else
        mpkg::warn "no system CA bundle found; https verification will fail."
        mpkg::warn "install ca-certificates, or set SSL_CERT_FILE and re-run."
    fi
}

# Programs that do not use this OpenSSL's default CAfile find the same trust
# store through SSL_CERT_FILE.
mpkg_shell_env() {
    printf '%s\n' '[ -r "${MPKG_PREFIX}/ssl/cert.pem" ] && export SSL_CERT_FILE="${MPKG_PREFIX}/ssl/cert.pem"'
}

mpkg_verify() {
    mpkg::have_shared_lib ssl && mpkg::have_shared_lib crypto && return 0
    mpkg::err "libssl.so / libcrypto.so are not linkable from ${MPKG_PREFIX}/lib"
    return 1
}
