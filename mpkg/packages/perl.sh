mpkg_inherit srccommon

MPKG_TITLE="Perl"
MPKG_DESC="Perl 5 interpreter"
MPKG_HOMEPAGE="https://www.perl.org/"
MPKG_PROBE_CMD="perl"
MPKG_REQUIRES_CMD=(cc make)

# Even minor versions are stable (5.42.x); odd ones (5.43.x) are development.
MPKG_LISTING_URL="https://www.cpan.org/src/5.0/"
MPKG_TAG_PATTERN='perl-5\.[0-9]*[02468]\.[0-9]+\.tar\.gz'
MPKG_TARBALL_URL='https://www.cpan.org/src/5.0/${tag}.tar.gz'
MPKG_INTREE=1

# Perl's Configure is metaconfig, not autoconf: it takes -D settings instead of
# --prefix, and -des answers every question with its default. With a non-/usr
# prefix it would put manpages in ${prefix}/man; send them to share/man like
# every other package.
mpkg_configure() {
    local dest="${MPKG_SOFT}/${MPKG_DEST_NAME}"
    mpkg::step "configuring"
    mpkg::run sh ./Configure -des \
        -Dprefix="${dest}" \
        -Dman1dir="${dest}/share/man/man1" \
        -Dman3dir="${dest}/share/man/man3" \
        -Doptimize=-O2 \
        || mpkg::stage_failed "${MPKG_NAME}: Configure failed"
}

# XS modules exercise dynamic loading, which a broken build usually loses.
mpkg_verify() {
    local bin="${MPKG_SOFT}/${MPKG_DEST_NAME}/bin/perl"
    if ! "${bin}" -MDigest::SHA -MTime::HiRes -e 1 >/dev/null 2>&1; then
        mpkg::err "the new perl does not run or cannot load XS modules"
        return 1
    fi
    mpkg::step "$("${bin}" -e 'print "perl $^V"')"
}
