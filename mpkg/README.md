# mpkg

A small package manager for a user-owned prefix (`$HOME/.local` by default).
It downloads, builds, links, tracks and removes the handful of tools this
workspace needs, on machines where there is no root and no system package
manager worth using.

```
./install.sh                    # bootstrap the whole workspace
./install.sh mpkg               # just mpkg itself, as ~/.local/bin/mpkg
mpkg install git                # one package, dependencies first
mpkg update                     # what has a newer release upstream?
mpkg doctor --fix               # check the prefix, repair what is repairable
```

mpkg installs itself like any other executable: the `mpkg` package copies
`mpkg/` and `nvim/` into `$MPKG_PREFIX/soft/mpkg-<version>/libexec/mpkg` and
links a `bin/mpkg` wrapper into `$MPKG_PREFIX/bin`. The version is
`MPKG_VERSION_STR` plus a hash of the copied files, so installing again after
the checkout changed replaces the tree. The installed copy remembers its
checkout; after a `git pull` there, `mpkg upgrade mpkg` picks up the changes.

## Layout

```
mpkg/
  mpkg                CLI entry point
  lib/
    core.sh           platform detection, prefix layout, logging, build flags
    util.sh           downloads, release discovery, version compare, templates
    class.sh          the inheritance mechanism (mpkg_inherit / mpkg_super)
    registry.sh       package discovery and metadata
    depsolve.sh       topological dependency resolution
    db.sh             installed-package database
    link.sh           symlinking a package tree into the prefix
    engine.sh         install / remove orchestration
    venv.sh           environments: extra symlink views of the store
    doctor.sh         checking the prefix and its links, and repairing them
    update.sh         checking upstream for newer releases
  packages/
    *common.sh        base classes
    <name>.sh         one file per package
```

Each package installs into its own tree, `$MPKG_PREFIX/soft/<name>-<version>`,
and is then symlinked into `$MPKG_PREFIX`. Versions never collide, and removing
a package is exact: the link manifest says which paths it owns.

## Commands

| command | what it does |
| --- | --- |
| `install <pkg>...` | resolve dependencies and install, in order |
| `remove <pkg>...` | unlink and delete; refuses if something still needs it |
| `upgrade [pkg]...` | rebuild anything whose upstream version moved on |
| `update [pkg]...` | check upstream for newer versions; installs nothing (see below) |
| `list` / `available` | installed / installable |
| `info <pkg>` | metadata, dependencies, install state |
| `deps <pkg>` / `order <pkg>...` | dependency tree / resolved install order |
| `link`, `unlink`, `relink`, `prune` | repair the symlink farm |
| `adopt` | register trees already in `soft/` that predate the database |
| `doctor [--fix]` | check the prefix and every link in it (see below) |
| `venv <sub> ...` | environments: create, add, rm, update, list, delete, activate, run |
| `gc` | delete store trees that nothing uses |
| `env` | the shell snippet this prefix needs |
| `log <pkg>` | the last build log |

Useful flags: `--prefix DIR`, `-j N`, `-n/--dry-run`, `-f/--force`, `--fix`, `--auto`,
`--force-all`, `--no-deps`, `-k/--keep-going`, `-v/--verbose`, `--keep-work`.

## Updates and upgrade notices

`mpkg update` asks upstream what each installed package's newest release is
-- the discover stage `upgrade` starts with, and nothing after it -- and lists
what is behind:

```
$ mpkg update
==> checking 19 package(s) for newer releases
  openssl              4.0.2            -> 4.0.3
  ruby                 4.0.7            -> 4.0.8
2 upgrade(s) available. Install with: mpkg upgrade [pkg...]
  not checked, updated by their own installers: nodejs oh-my-zsh rust starship uv
```

The result is cached in `var/mpkg/updates`; `mpkg list` marks those packages.
Packages run by their own installers (rustup, nvm, uv, starship, Oh My Zsh)
are not checked, and neither are config and meta packages. For `mpkg` itself
a "newer version" means the checkout has changed since it was installed.

With `shell-config` installed, every interactive bash/zsh says so at start:

```
mpkg: 2 upgrade(s) available: openssl ruby  (mpkg upgrade)
```

That reads the cache only, so starting a shell never waits on the network.
When the last check is older than `MPKG_UPDATE_INTERVAL` minutes (default
1440, a day) the shell also starts `mpkg update --auto` in the background,
and the next shell has the answer. `--auto` is silent and does nothing if a
check is recent or already running. `MPKG_NO_UPDATE_CHECK=1` turns off both
the notice and the background check.

## Doctor

`mpkg doctor` checks the build tools, the database, every link, the trust
store, the shared libraries curl and openssl provide, and git's https helper.
The link check compares each package's manifest with what is really in the
prefix (and in each environment):

| finding | meaning | `--fix` does |
| --- | --- | --- |
| missing | the link is gone | relinks the package |
| pointing elsewhere | a link is there, to the wrong place | relinks the package |
| replaced by files | a real file sits where the link was | nothing; `mpkg link --force <pkg>` moves it to `*.mpkg-orig` |
| dangling | the link is right but its file is gone from the store tree | reinstalls the package |
| tree is gone | the whole store tree was deleted | reinstalls the package |

Links nobody owns that point at nothing are reported too: into the store
(left by a package that is gone; `--fix` and `mpkg prune` delete them), or
anywhere else (a warning; mpkg never deletes what it did not make). After
repairing, `--fix` runs the checks again, so what it prints last is the state
it left.

## Environments

The store (`soft/`) holds every package tree once; the base prefix is one view
of it. `mpkg venv` makes more views -- named symlink farms under
`$MPKG_PREFIX/envs/<name>` -- in the spirit of a Python venv or a Nix profile,
at the cost of a few symlinks:

```
mpkg venv create media ffmpeg          # ffmpeg plus its dependencies
mpkg venv create --isolated tools rg fd
mpkg_activate media                    # or: . ~/.local/envs/media/activate
mpkg_deactivate
mpkg venv run media -- ffmpeg -version # one command, no activation
mpkg venv list [media]
```

- **Pinning.** An environment keeps the exact tree it linked. `mpkg upgrade`
  and `mpkg remove` leave a tree alone while an environment uses it; it is
  deleted when the last user lets go (`venv update`, `venv rm`,
  `venv delete`). `venv list <env>` flags packages pinned behind the base.
- **Older versions.** `pkg@version` links any version still in the store,
  e.g. one another environment pinned before an upgrade. mpkg only builds the
  latest release, so a version never installed cannot be requested.
- **Isolation.** `--isolated` environments drop the base prefix from `PATH`,
  `LD_LIBRARY_PATH`, `LIBRARY_PATH`, `CPATH`, `PKG_CONFIG_PATH` and `MANPATH`
  when activated, so only their own packages (and the system) are visible.
- **Activation** is a POSIX script, so bash and zsh both work; it saves every
  variable it changes and `mpkg_deactivate` puts them back exactly. Activating
  a second environment leaves the first. `$MPKG_VENV` names the active one;
  the prompt gets a `(name)` prefix unless `MPKG_VENV_NO_PROMPT` is set.

Packages are still built and installed through the base prefix, because
configure scripts need their dependencies' headers and libraries there;
`venv add` installs anything missing into the base first. Packages managed by
their own installers (rust, nodejs, uv, rvm) have no tree and are skipped.
Libraries resolve through the base prefix's `lib/` at run time (rpath), so a
pinned tree keeps using the base's current copy of a shared library with the
same soname.

`mpkg gc` lists store trees nothing uses (failed builds, pre-database trees)
and deletes them after asking.

## Writing a package

Bash has no classes, so mpkg builds one by sourcing scripts in layers. A
package starts by inheriting a base class and then overrides only what differs:

```bash
# packages/curl.sh
mpkg_inherit srccommon

MPKG_TITLE="cURL"
MPKG_DEPENDS=(openssl)
MPKG_LISTING_URL="https://github.com/curl/curl/tags"
MPKG_TAG_PATTERN='curl-[0-9]+_[0-9]+_[0-9]+'
MPKG_TARBALL_URL='https://github.com/curl/curl/releases/download/${tag}/${tag//_/.}.tar.gz'

mpkg_discover() {
    mpkg_super discover || return 1      # run srccommon's version first
    MPKG_VERSION="${MPKG_VERSION//_/.}"  # then fix up the result
}
```

`mpkg_inherit` sources the base, then seals it: every method the layer defined
is copied to a level-tagged name and replaced by a dispatcher. The dispatcher
runs the most-derived implementation; `mpkg_super <method>` runs the nearest
one *below* the currently executing layer. That is what makes the override
above an extension rather than a replacement, at any inheritance depth.

### Base classes

| class | for | pipeline |
| --- | --- | --- |
| `pkgcommon` | root; discovery, linking, cleanup | — |
| `srccommon` | source tarball + autotools | discover, fetch, prepare, configure, build, install, link, cleanup |
| `gnucommon` | GNU FTP packages (derives every URL from the name) | as `srccommon` |
| `bincommon` | one pre-built executable from a release | discover, fetch, install, link |
| `tarcommon` | a pre-built tarball with `bin/ lib/ share/` inside | discover, fetch, install, link |
| `ghcommon` | executables inside a GitHub release archive (ripgrep, fd, fzf) | discover, fetch, install, link |
| `mesoncommon` | source tarball built with Meson (`--libdir=lib`) | as `srccommon` |
| `gnomecommon` | GNOME projects, newest stable (even minor) from `cache.json` (gtk) | as `mesoncommon` |
| `pwmtcommon` | pwmt.org projects, URLs derived from the name (girara, zathura) | as `mesoncommon` |
| `cmakecommon` | source tarball built with CMake (poppler) | as `srccommon` |
| `scriptcommon` | upstream installer scripts (rustup, nvm, uv) | guard, fetch, install |
| `metacommon` | dependencies only (`workspace`, `toolchain`) | — |

### Hooks

`mpkg_describe` runs after the package body, for defaults that need
`MPKG_NAME`. `mpkg_env` runs on *every* invocation, installed or not, and is
where a package extends `CPATH` / `PATH` for the packages built after it.
`mpkg_post_install` runs only after an actual install. `mpkg_verify` runs last
and can fail the install — `git` uses it to refuse a build with no https
support.

Templates in `MPKG_TARBALL_URL`, `MPKG_ASSET`, `MPKG_MAKE_VARS` and friends are
single-quoted and expanded once the version is known. Available placeholders:
`${name} ${tag} ${version} ${asset}`, plus any exported variable
(`${MPKG_PREFIX}`, `${MPKG_SOFT}`) and the platform in the spellings release
assets use:

| variable | Linux x86_64 | Linux arm64 | macOS arm64 |
| --- | --- | --- | --- |
| `${_OS}` | `linux` | `linux` | `macos` |
| `${_GOOS}` | `linux` | `linux` | `darwin` |
| `${_ARCH}` | `amd64` | `arm64` | `arm64` |
| `${_UARCH}` | `x86_64` | `aarch64` | `aarch64` |
| `${_TRIPLE}` | `x86_64-unknown-linux-musl` | `aarch64-unknown-linux-musl` | `aarch64-apple-darwin` |

A tree's top-level `.mpkg/` directory is never linked into the prefix. It is
for a payload that other links point into but that should not be spread over
the prefix itself: `go` keeps its GOROOT (some 15000 files) in
`.mpkg/goroot` and links only `bin/go` and `bin/gofmt`.

Instead of a listing URL, a package can set `MPKG_GITHUB_REPO="owner/repo"`;
discovery then takes that repository's latest release, and the version is the
first dotted number in its tag (`v1.2.3`, `release-2.1.13-stable`, `3.7c`).

To see which assets another platform would get, override detection:
`MPKG_OS=macos MPKG_ARCH=arm64`.

## Notes on two bugs this design fixes

**Symlinks were dropped when linking.** The original walk used
`find -type f`, so for a shared library only `libcurl.so.4.8.0` was linked and
the `libcurl.so` / `libcurl.so.4` symlinks were not. With no
`$PREFIX/lib/libcurl.so`, `-lcurl` fell back to the static `libcurl.a`, whose
link fails on undefined zlib/zstd symbols. git's `configure` decides https
support by *linking* a libcurl test program, so it set `NO_CURL` and produced a
git with no `git-remote-http`/`git-remote-https` — `git clone https://...`
then died with "unable to find remote helper for 'https'". `mpkg::link_entries`
now takes `-type f -o -type l`, and `git`'s `mpkg_verify` fails loudly rather
than shipping a git that cannot clone.

**No trust store.** OpenSSL is installed with `--openssldir=$PREFIX/ssl`, and
`install_ssldirs` leaves `certs/` empty, so anything linked against it rejects
every certificate. `openssl`'s `mpkg_post_install` points `$PREFIX/ssl/cert.pem`
at the system CA bundle, and `curl` is configured with an explicit
`--with-ca-bundle` instead of relying on configure's probe.

## Editor and PDF viewer packages

- `nvim-config` copies the repository's `nvim/` (a Lua configuration:
  lazy.nvim, the built-in LSP client, nvim-treesitter's main branch) to
  `~/.config/nvim`, then installs the plugins at the commits in
  `lazy-lock.json` and the tree-sitter parsers, so the first start downloads
  nothing. Its version is a hash of `nvim/`; a configuration mpkg did not
  write, or one edited in place, is moved to `~/.config/nvim.mpkg-backup.<time>`
  first. It pulls in `tree-sitter` (the CLI nvim-treesitter builds parsers
  with) and `jdk` (Eclipse Temurin LTS: `java`, `javac`; the tree lives in
  `libexec/jdk`, which is `JAVA_HOME`).
- `mason` installs the servers listed in `nvim/lua/config/languages.lua`
  (the same list the configuration gives mason-lspconfig), headless and
  synchronously, after the runtimes Mason's installers need (nodejs, uv, rust,
  jdk). Names with no Mason package are skipped with a warning.
- `zathura-pdf-poppler` pulls in `zathura`, `girara`, `gtk` (GTK 4) and
  `poppler`. The libraries below GTK (glib, cairo, pango, ...) come from the
  system when pkg-config finds them, otherwise from GTK's Meson wraps. zathura
  is built to look for plugins in `$MPKG_PREFIX/lib/zathura`, where each
  plugin's links land. GTK's GSettings schemas are compiled in
  `$MPKG_PREFIX/share/glib-2.0/schemas`, found through `XDG_DATA_DIRS`.

## Go

`mpkg install go` installs the newest stable Go from go.dev, after checking
the archive against the SHA-256 go.dev publishes. The go command finds its
GOROOT from its own location, so nothing has to set GOROOT; `env.sh` puts
`$GOBIN`, or else `$GOPATH/bin` (`~/go/bin` by default), on `PATH`, so what
`go install` builds is found. `go` is part of `workspace`.

## Environment

`MPKG_PREFIX` (default `$HOME/.local`), `MPKG_WORK`, `MPKG_JOBS`,
`MPKG_GNU_MIRROR`, `SSL_CERT_FILE`, `MPKG_OS`, `MPKG_ARCH`, `MPKG_MAKE`
(GNU make; `gmake` is picked up on the BSDs), `MPKG_GIT_RUST` (`yes`/`no`;
by default git's Rust parts are built only when a working `cargo` exists,
otherwise git is built with `NO_RUST`), `MPKG_UPDATE_INTERVAL` and
`MPKG_NO_UPDATE_CHECK` (see "Updates and upgrade notices").

Commands that change the prefix take a lock, `$MPKG_PREFIX/var/mpkg/lock`, so
two mpkg runs cannot interleave. A lock left by a crashed run on the same host
is taken over; one held from another host (a shared NFS home) is reported
with the command that clears it. A build that fails has its half-installed
tree removed from `soft/` (kept with `--keep-work`).

## Shell setup

`mpkg install shell-config` writes two files and sources them from each
shell's startup files through a `# >>> mpkg >>>` block; nothing else in those
files is touched, and `mpkg remove shell-config` takes the blocks out again.

| file | contents | sourced from |
| --- | --- | --- |
| `share/mpkg/env.sh` | environment variables only (POSIX sh, re-sourcing is harmless) | `~/.profile`, `~/.bash_profile` (only if it exists), `~/.bashrc`, `~/.zprofile`, `~/.zshrc` |
| `share/mpkg/interactive.sh` | `mpkg_activate`, Oh My Zsh, starship, nvm, RVM, the upgrade notice | `~/.bashrc`, `~/.zshrc` |

bash and zsh files are only written when that shell is installed, and Oh My
Zsh is only a dependency where zsh exists. `env.sh` moves the prefix to the
front of `PATH` rather than only adding it, so macOS's `path_helper` cannot
push it behind `/usr/bin`. `mpkg env` prints `env.sh`.

mpkg needs bash 4 or newer. On macOS, where `/bin/bash` is 3.2, it re-runs
itself under Homebrew's or MacPorts' bash when one is installed. State lives in
`$MPKG_PREFIX/var/mpkg/{db,log,work}`.
