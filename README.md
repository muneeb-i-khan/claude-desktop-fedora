# Claude Desktop for Fedora (unofficial RPM)

Native `.rpm` packages of the official **Claude Desktop** app (Chat, Cowork and the Claude Code tab) for Fedora Workstation, KDE Plasma, and Fedora Atomic desktops (Silverblue / Kinoite), for **x86_64** and **aarch64**.

A GitHub Actions workflow checks Anthropic's apt repository every 6 hours, repackages each new release, publishes it as a GitHub Release, and updates a DNF repository so `sudo dnf upgrade` keeps you current.

> **Unofficial.** Anthropic's own Linux docs support Ubuntu and Debian only. This package is community-maintained and not tested or endorsed by Anthropic. See the [disclaimer](#legal-disclaimer).

> **Using a fork?** Replace `muneeb-i-khan/claude-desktop-fedora` in the URLs below with your own `user/repo`; the `github.io` hostname uses your lowercase username. The workflow fills in the right values automatically in the files it generates.

## Install with DNF (recommended)

```bash
# DNF 5 (Fedora 41+)
sudo dnf config-manager addrepo --from-repofile=https://muneeb-i-khan.github.io/claude-desktop-fedora/claude-desktop.repo
# DNF 4 (older releases): sudo dnf config-manager --add-repo https://muneeb-i-khan.github.io/claude-desktop-fedora/claude-desktop.repo

sudo dnf install claude-desktop
```

Updates arrive with your normal `sudo dnf upgrade`. Launch **Claude** from your app launcher, or run `claude-desktop`.

## Install a single RPM

Download the `.rpm` for your architecture from the [Releases page](https://github.com/muneeb-i-khan/claude-desktop-fedora/releases/latest), then:

```bash
sha256sum -c SHA256SUMS --ignore-missing
sudo dnf install ./claude-desktop-*.rpm
```

A directly installed RPM does not update itself; use the DNF repository above for that.

## Fedora Silverblue / Kinoite (rpm-ostree)

The app installs into `/usr/lib/claude-desktop` (not `/opt`), so it layers cleanly.

With the repository, which also gives you updates through `rpm-ostree upgrade`:

```bash
sudo curl -fLo /etc/yum.repos.d/claude-desktop.repo https://muneeb-i-khan.github.io/claude-desktop-fedora/claude-desktop.repo
rpm-ostree install claude-desktop
systemctl reboot
```

Or from a downloaded RPM:

```bash
rpm-ostree install ./claude-desktop-*.rpm
systemctl reboot
```

## Claude Cowork (KVM virtual machine)

Cowork runs its tasks in a QEMU/KVM virtual machine hosted by the app.

1. **Enable hardware virtualization** (VT-x / AMD-V) in your firmware settings.
2. **Install the VM packages.** They are weak dependencies, so DNF normally installs them already. If you installed with `--setopt=install_weak_deps=False`:

   ```bash
   sudo dnf install qemu-kvm edk2-ovmf virtiofsd    # aarch64: edk2-aarch64 instead of edk2-ovmf
   ```

   On Silverblue/Kinoite: `rpm-ostree install qemu-kvm edk2-ovmf virtiofsd` and reboot.
3. **Join the `kvm` group**, then log out and back in. Anthropic's docs say Cowork also needs `/dev/vhost-vsock`, which only `kvm` group members can open, so join the group even if `/dev/kvm` already works for you:

   ```bash
   sudo usermod -aG kvm "$USER"
   ```

4. **Check the devices exist:**

   ```bash
   ls -l /dev/kvm /dev/vhost-vsock
   ```

   If `/dev/vhost-vsock` is missing, loading the module normally creates it (not verified on every kernel):

   ```bash
   sudo modprobe vhost_vsock
   echo vhost_vsock | sudo tee /etc/modules-load.d/vhost_vsock.conf
   ```

The app checks these requirements once at launch, so restart it after changing anything.

## Wayland and launch options

`/usr/bin/claude-desktop` is a small wrapper around the upstream binary. On a Wayland session (`XDG_SESSION_TYPE=wayland`) it adds `--ozone-platform=wayland --enable-features=UseOzonePlatform` so the app runs natively instead of through XWayland.

| To do this | Do this |
| --- | --- |
| Force X11/XWayland | `CLAUDE_USE_X11=1 claude-desktop` |
| Choose the platform yourself | Pass `--ozone-platform=...` (or `--ozone-platform-hint=...`); the wrapper then adds nothing |
| Always pass extra flags | Put them in `~/.config/claude-desktop-flags.conf` (whitespace-separated, `#` comments) |

## Sign-in and keyring

Claude Desktop stores your sign-in in the desktop keyring (GNOME Keyring or KDE Wallet). If it can't reach an unlocked keyring you will be asked to sign in each launch. On KDE Plasma, don't install GNOME Keyring alongside KDE Wallet; Anthropic reports that the two conflict.

## How the packages are built

1. `scripts/upstream.sh` downloads Anthropic's signing key and **refuses to continue unless its fingerprint is exactly `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`** (the fingerprint in Anthropic's own install docs).
2. It verifies the repo's `InRelease` signature with `gpgv`, checks the `Packages` index hash against it, picks the newest version published for both architectures, then checks the `.deb`'s size and SHA-256 against the index.
3. `packaging/claude-desktop.spec` unpacks the `.deb` with `ar` and `tar` (no `alien`) into `/usr/lib/claude-desktop`. It replaces upstream's `/usr/bin/claude-desktop` symlink with the wrapper, and ships what upstream's `postinst` would have created at install time (GNOME search provider, MIME types) as ordinary package files. Upstream's apt-repository registration and AppArmor profile are intentionally **not** reproduced.
4. The workflow runs `rpmlint` (non-blocking; known noise for prebuilt binaries is filtered in `packaging/rpmlint.toml`), checks `rpm -qpi` / `rpm -qpl`, and smoke-tests `dnf install` plus `rpm -V` in a clean `fedora:latest` container.

The spec disables debuginfo, stripping and automatic dependency scanning (`AutoReqProv: no`) because the payload is prebuilt Chromium/Electron/Node. Runtime dependencies are declared by hand.

### Build locally

On Fedora, with `rpm-build binutils tar xz zstd gnupg2 curl gawk desktop-file-utils` installed:

```bash
./scripts/build-rpm.sh            # newest upstream version
./scripts/build-rpm.sh 5.1231.2   # a specific version
ls dist/
```

Set `PKG_RELEASE=2` to rebuild the same upstream version with a bumped RPM release.

## Running your own copy of the repository

1. Fork or push this repository to GitHub.
2. **Settings → Pages → Build and deployment → Source: GitHub Actions.**
3. **Settings → Actions → General → Workflow permissions:** allow read and write (the workflow also requests the permissions it needs per job).
4. Run **Actions → Build Claude Desktop RPM → Run workflow**. Later runs happen on push to `main` and every 6 hours; a version that already has a release is skipped. Use the `force` input to rebuild and republish an existing version.

GitHub disables scheduled workflows in repositories with no activity for 60 days; re-enable the workflow in the Actions tab if that happens.

### Optional: sign the packages

Without signing, the generated `.repo` file sets `gpgcheck=0` (transport is HTTPS, and upstream's signature and hashes are verified at build time). To sign RPMs and repository metadata, add these repository secrets; the `.repo` file then enables `gpgcheck=1` and `repo_gpgcheck=1` and the public key is published at `https://muneeb-i-khan.github.io/claude-desktop-fedora/RPM-GPG-KEY-claude-desktop-fedora`:

- `RPM_GPG_PRIVATE_KEY`: ASCII-armored private key (`gpg --armor --export-secret-keys <id>`)
- `RPM_GPG_PASSPHRASE`: passphrase, if the key has one

## Repository layout

```
.
├── .github/workflows/build-rpm.yml      # check -> build (x86_64, aarch64) -> release -> Pages repo
├── packaging/
│   ├── claude-desktop.spec              # RPM spec
│   ├── claude-desktop-wrapper.sh        # /usr/bin/claude-desktop launcher
│   ├── claude-desktop.repo.in           # template for the generated .repo file
│   └── rpmlint.toml                     # filters for expected rpmlint noise
├── scripts/
│   ├── upstream.sh                      # verified lookup + download from Anthropic's apt repo
│   ├── build-rpm.sh                     # fetch + rpmbuild
│   └── make-repo.sh                     # createrepo_c + .repo file for GitHub Pages
├── LICENSE                              # MIT (packaging only)
└── README.md
```

## Legal disclaimer

This is an **unofficial community packaging project**. It is not affiliated with, authorized, maintained, sponsored or endorsed by Anthropic PBC. "Claude" and "Anthropic" are trademarks of Anthropic.

The Claude Desktop application is **proprietary software owned by Anthropic**. This repository contains only packaging scripts, a spec file and CI configuration, licensed under the [MIT License](LICENSE). The RPMs it builds contain Anthropic's unmodified application files, obtained from Anthropic's official apt repository, and remain subject to Anthropic's own terms and policies. Using the app requires accepting those terms. Anthropic does not officially support Fedora; do not ask Anthropic for support with these packages. Software is provided "as is", without warranty of any kind.
