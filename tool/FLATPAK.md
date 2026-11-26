# Build Telegrive as a Flatpak

Linux Mint can install Flatpak applications. From the repository root, install Docker and Flatpak tooling, then build the application:

```bash
sudo apt install docker.io flatpak flatpak-builder
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
# Log out and back in after installing Docker if your account needs Docker group access.
tool/build_flatpak.sh x64
```

The build produces `build/linux-release/Telegrive-<version>-x64.flatpak`. The first run builds TDLib and the Linux app in Docker, then packages the AppImage's collected shared libraries into a Flatpak. This avoids requiring Linux Mint to have the app's AppIndicator, libsecret, or mpv libraries installed separately.

Install the generated bundle and its Flathub runtime:

```bash
flatpak install --user --bundle build/linux-release/Telegrive-*-x64.flatpak
```

Launch **Telegrive** from the Mint application menu, or run:

```bash
flatpak run dev.ragoose.telegrive
```

The app requests network access, the Wayland/X11 display, the desktop keyring and notifications. It uses the XDG file chooser portal and grants access to files you select; it does not request unrestricted access to your home directory. For ARM64, use `tool/build_flatpak.sh arm64`.

The output is a locally built bundle, not a Flathub-published release. See `tool/build_linux.sh` and `tool/build_tdlib_linux.sh` for the underlying Linux build requirements.
