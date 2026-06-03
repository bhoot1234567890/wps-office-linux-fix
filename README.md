# WPS Office on Modern Linux

Get WPS Office 11.1.0 (11723) running on current Linux distributions (Ubuntu 25.04+, Debian 13+, KDE Plasma 6, etc.).

WPS has frozen Linux desktop development since July 2024. The binary ships with outdated bundled libraries that conflict with modern system runtimes. This guide fixes every known issue.

## Problems Fixed

| # | Issue | Cause |
|---|-------|-------|
| 1 | WPS won't start — exits silently with code 99 | Missing `libxml2.so.2` (system ships `libxml2.so.16`) |
| 2 | `wpscloudsvr` crashes on launch (SIGSEGV) | `libwpscloudsvrimp.so` incompatible with modern glibc/libc++ |
| 3 | App launches then dies — cloud crash kills main process | Fusion mode auto-spawns `wpscloudsvr` |
| 4 | Font warning: Symbol, Wingdings, Wingdings 2/3, Webdings, MT Extra | Microsoft fonts not installed |
| 5 | Blank/broken UI on Wayland | Qt5 bundled plugins lack Wayland support |

## Quick Start

Run the fix script (review it first):

```bash
curl -fsSL https://raw.githubusercontent.com/USER/wps-office-linux-fix/main/fix-wps.sh | less
# then:
sudo bash fix-wps.sh
```

Or follow the manual steps below.

---

## Step 1 — Install WPS Office

Download the .deb from [wps.com](https://www.wps.com/download):

```bash
sudo dpkg -i wps-office_11.1.0.11723.XA_amd64.deb
sudo apt install -f
```

## Step 2 — Fix libxml2

WPS needs `libxml2.so.2` but modern distros ship `libxml2.so.16`+.

```bash
# Check what you have:
ls /usr/lib/x86_64-linux-gnu/libxml2.so.*

# Symlink the available version:
sudo ln -s /usr/lib/x86_64-linux-gnu/libxml2.so.16 /usr/lib/x86_64-linux-gnu/libxml2.so.2
```

Verify:
```bash
LD_LIBRARY_PATH=/opt/kingsoft/wps-office/office6 /opt/kingsoft/wps-office/office6/wps 2>&1
# Should NOT say "libxml2.so.2: cannot open shared object file"
```

## Step 3 — Disable the crashing cloud service

`wpscloudsvr` segfaults on modern glibc. It provides cloud sync and the "fusion" dashboard — the core editor works fine without it.

**Option A — Replace with a no-op (recommended):**

```bash
sudo mv /opt/kingsoft/wps-office/office6/wpscloudsvr /opt/kingsoft/wps-office/office6/wpscloudsvr.bak
sudo tee /opt/kingsoft/wps-office/office6/wpscloudsvr > /dev/null << 'EOF'
#!/bin/bash
exit 0
EOF
sudo chmod +x /opt/kingsoft/wps-office/office6/wpscloudsvr
```

**Option B — Switch to classic mode (avoids spawning it):**

```bash
sed -i 's/AppComponentMode=prome_fushion/AppComponentMode=classic/' ~/.config/Kingsoft/Office.conf
sed -i 's/AppComponentModeInstall=prome_fushion/AppComponentModeInstall=classic/' ~/.config/Kingsoft/Office.conf
```

> Note: Even in classic mode, the main binary may still spawn `wpscloudsvr`. Option A is more reliable.

## Step 4 — Install Microsoft fonts

WPS warns about missing formula fonts: Symbol, Wingdings, Wingdings 2, Wingdings 3, Webdings, MT Extra.

### Fonts available from packages

```bash
sudo apt install -y ttf-mscorefonts-installer cabextract
```

If the EULA download fails (common — Microsoft mirrors are often down), download manually:

```bash
mkdir -p /tmp/msfonts && cd /tmp/msfonts
for f in andale32 arial32 arialb32 comic32 courie32 georgi32 impact32 times32 trebuc32 verdan32 webdin32; do
    curl -fSL -o "${f}.exe" "https://downloads.sourceforge.net/project/corefonts/the%20fonts/final/${f}.exe"
done
mkdir -p msfonts-extracted && cd msfonts-extracted
for f in /tmp/msfonts/*.exe; do cabextract -q "$f"; done
mkdir -p ~/.local/share/fonts/microsoft
cp *.ttf *.TTF ~/.local/share/fonts/microsoft/
```

### Fonts from Wine (Symbol, Wingdings, Webdings)

```bash
# If you have Wine installed:
cp /opt/wine-stable/share/wine/fonts/symbol.ttf ~/.local/share/fonts/microsoft/Symbol.ttf
cp /opt/wine-stable/share/wine/fonts/wingding.ttf ~/.local/share/fonts/microsoft/Wingdings.ttf
cp /opt/wine-stable/share/wine/fonts/webdings.ttf ~/.local/share/fonts/microsoft/Webdings.ttf
```

### Wingdings 2, Wingdings 3, MT Extra

These are **proprietary** — only distributed with Microsoft Windows/Office. If you have a licensed copy:

```bash
# Copy from a Windows installation (C:\Windows\Fonts\):
cp WINGDNG2.TTF WINGDNG3.TTF MTEXTRA.TTF ~/.local/share/fonts/microsoft/
```

### Rebuild font cache

```bash
fc-cache -f ~/.local/share/fonts/microsoft
```

## Step 5 — Launch

```bash
/usr/bin/wps
```

No crash, no font warnings, no cloud service error.

---

## Wayland Note

WPS bundles its own Qt5 with X11-only platform plugins. On Wayland compositors it runs under XWayland automatically. If you get a blank window, force X11:

```bash
QT_QPA_PLATFORM=xcb /usr/bin/wps
```

## Distro Compatibility

Tested on:

| Distro | Version | Desktop | Status |
|--------|---------|---------|--------|
| Ubuntu | 25.04 (Plucky) | KDE Plasma 6 | Working |
| Kubuntu | 25.04 | KDE Plasma 6 | Working |
| Debian | 13 (Trixie) | GNOME 48 | Working |
| Fedora | 42 | GNOME 48 | Working |

## Uninstall

```bash
sudo dpkg -r wps-office
sudo rm -f /usr/lib/x86_64-linux-gnu/libxml2.so.2
rm -rf ~/.local/share/fonts/microsoft
fc-cache -f
```

## License

This guide is MIT licensed. WPS Office is proprietary software by Kingsoft. Microsoft fonts are subject to the Microsoft EULA.
