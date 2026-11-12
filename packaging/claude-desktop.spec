# Unofficial RPM repackaging of Anthropic's official Claude Desktop .deb.
#
# Build with scripts/build-rpm.sh, or by hand:
#   rpmbuild -bb packaging/claude-desktop.spec \
#     --define "upstream_version 5.1231.2" --define "_sourcedir $PWD/sources"
# where sources/ holds claude-desktop_<version>_<amd64|arm64>.deb and
# claude-desktop-wrapper.sh.

%{!?upstream_version:%{error:define upstream_version, e.g. --define "upstream_version 5.1231.2"}}
%{!?pkg_release:%global pkg_release 1}

# The payload is prebuilt Chromium/Electron/Node: no debuginfo, no stripping,
# no bytecompile/rpath post-processing, and no automatic dependency scan (the
# bundled libffmpeg/vulkan/swiftshader libraries would produce bogus Requires
# and Provides). Real dependencies are declared by hand below.
%global debug_package %{nil}
%global __strip /bin/true
%global __os_install_post %{nil}
%global _build_id_links none
%global _missing_build_ids_terminate_build 0
AutoReqProv: no

# Lives in /usr/lib (not /opt) so it layers cleanly with rpm-ostree on
# Silverblue/Kinoite. %%{_libdir} is deliberately not used: it is lib64 on x86_64.
%global appdir %{_prefix}/lib/claude-desktop

# Map the RPM architecture to the Debian architecture used upstream.
%ifarch x86_64
%global debarch amd64
%endif
%ifarch aarch64
%global debarch arm64
%endif

Name:           claude-desktop
Version:        %{upstream_version}
Release:        %{pkg_release}
Summary:        Claude Desktop (Chat, Cowork and Claude Code) - unofficial Fedora repackaging
# The application is Anthropic's proprietary software; this spec only repackages it.
License:        LicenseRef-Anthropic-Proprietary
URL:            https://claude.ai
Source0:        claude-desktop_%{version}_%{debarch}.deb
Source1:        claude-desktop-wrapper.sh

ExclusiveArch:  x86_64 aarch64

BuildRequires:  binutils
BuildRequires:  tar
BuildRequires:  xz
BuildRequires:  zstd
BuildRequires:  desktop-file-utils

Requires:       gtk3
Requires:       libnotify
Requires:       nss
Requires:       libXScrnSaver
Requires:       libXtst
Requires:       xdg-utils
Requires:       at-spi2-core
Requires:       libuuid
Requires:       mesa-libgbm
Requires:       alsa-lib
Requires:       libdrm
Requires:       libsecret
Requires:       xdg-desktop-portal
Requires:       (xdg-desktop-portal-gtk or xdg-desktop-portal-gnome or xdg-desktop-portal-kde)
Requires(post):   desktop-file-utils
Requires(postun): desktop-file-utils

# Claude Cowork runs tasks in a QEMU/KVM virtual machine. Weak dependencies, so
# minimal installs are not forced to pull in virtualization.
Recommends:     qemu-kvm
%ifarch x86_64
Recommends:     edk2-ovmf
%endif
%ifarch aarch64
Recommends:     edk2-aarch64
%endif
Recommends:     virtiofsd
# GNOME Shell search provider
Recommends:     gjs

%description
Claude Desktop is Anthropic's desktop application for Claude, including Chat,
Cowork and the Claude Code tab.

This package is an UNOFFICIAL community repackaging of the .deb that Anthropic
publishes in its official apt repository (signature and hashes are verified
at build time). It is not affiliated with or endorsed by Anthropic. The
application itself is proprietary software owned by Anthropic.

%prep
%setup -q -c -T
mkdir deb root
cd deb
ar x %{SOURCE0}
# data.tar.{xz,zst,gz}: tar detects the compression itself.
tar -xpf data.tar.* -C ../root --no-same-owner

%build
# Nothing to build: prebuilt binaries.

%install
install -d %{buildroot}%{appdir}
cp -a root/usr/lib/claude-desktop/. %{buildroot}%{appdir}/
# Chromium's SUID sandbox helper (fallback when unprivileged user namespaces
# are unavailable). rpm records the mode found in the buildroot.
chmod 4755 %{buildroot}%{appdir}/chrome-sandbox

# Wrapper replaces upstream's /usr/bin/claude-desktop symlink.
install -Dpm0755 %{SOURCE1} %{buildroot}%{_bindir}/claude-desktop

# Desktop entry + hicolor icons
install -Dpm0644 root/usr/share/applications/com.anthropic.Claude.desktop \
    %{buildroot}%{_datadir}/applications/com.anthropic.Claude.desktop
cp -a root/usr/share/icons/. %{buildroot}%{_datadir}/icons/

# What upstream's postinst copies into place, shipped directly instead.
sp=root/usr/lib/claude-desktop/resources/gnome-search-provider
install -Dpm0644 $sp/com.anthropic.Claude.search-provider.ini \
    %{buildroot}%{_datadir}/gnome-shell/search-providers/com.anthropic.Claude.search-provider.ini
install -Dpm0644 $sp/com.anthropic.Claude.SearchProvider.service \
    %{buildroot}%{_datadir}/dbus-1/services/com.anthropic.Claude.SearchProvider.service
install -Dpm0644 root/usr/lib/claude-desktop/resources/linux-mime/com.anthropic.Claude.xml \
    %{buildroot}%{_datadir}/mime/packages/com.anthropic.Claude.xml

install -Dpm0644 root/usr/share/doc/claude-desktop/copyright \
    %{buildroot}%{_licensedir}/%{name}/copyright

# /usr/bin/ccd (terminal launcher), only when this upstream build ships one.
echo %{_bindir}/claude-desktop > extra.files
if [ -x %{buildroot}%{appdir}/resources/bin/ccd ]; then
    ln -s ../lib/claude-desktop/resources/bin/ccd %{buildroot}%{_bindir}/ccd
    echo %{_bindir}/ccd >> extra.files
fi

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/com.anthropic.Claude.desktop || :

%post
/usr/bin/update-desktop-database -q %{_datadir}/applications &>/dev/null || :
/usr/bin/gtk-update-icon-cache -q -t -f %{_datadir}/icons/hicolor &>/dev/null || :
/usr/bin/update-mime-database %{_datadir}/mime &>/dev/null || :

%postun
/usr/bin/update-desktop-database -q %{_datadir}/applications &>/dev/null || :
/usr/bin/gtk-update-icon-cache -q -t -f %{_datadir}/icons/hicolor &>/dev/null || :
/usr/bin/update-mime-database %{_datadir}/mime &>/dev/null || :

%files -f extra.files
%license %{_licensedir}/%{name}/copyright
%{appdir}/
%{_datadir}/applications/com.anthropic.Claude.desktop
%{_datadir}/icons/hicolor/*/apps/claude-desktop.png
%{_datadir}/gnome-shell/search-providers/com.anthropic.Claude.search-provider.ini
%{_datadir}/dbus-1/services/com.anthropic.Claude.SearchProvider.service
%{_datadir}/mime/packages/com.anthropic.Claude.xml

%changelog
* Thu Nov 12 2026 Claude Desktop Fedora packaging <noreply@users.noreply.github.com> - %{version}-%{pkg_release}
- Repackaged from Anthropic's official apt repository
