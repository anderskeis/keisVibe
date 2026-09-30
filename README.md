# Vibe Launcher for Omarchy

A bar widget for [Mistral Vibe](https://github.com/mistralai/mistral-vibe) on
Omarchy Quattro. Click **Vibe** to open a small, keyboard-friendly panel:

![Vibe launcher panel in the Omarchy bar](preview.png)

- **New session** (`N`) starts an interactive Vibe session.
- **Continue last session** (`C`) runs `vibe --continue`.
- **Choose a session** (`R`) opens Vibe's `--resume` picker.
- **Directory** (`D`) opens a directory box to set where Vibe starts.

Use Up/Down and Enter to choose an action, Esc to close the panel, and Tab to
switch to a neighboring bar panel. Sessions launch in `~/Work` if it exists,
otherwise in your home directory.

## Set the working directory in the panel

Press `D` (or click the directory row) to open a directory box before
starting a session. It is prefilled with the current directory:

- Type a path — `~/Projects` or an absolute path — and press `Enter`
- `Tab` completes the current path segment like a shell: a unique match
  completes fully, several matches extend to their longest common prefix,
  and matching is case-insensitive. Hidden folders are never offered.
  `Tab` on an empty field starts from `~`
- **Reset to default** (or press `X` in the main panel) restores the
  `~/Work`-or-home default
- `Esc` cancels without changing anything

The confirmed choice is saved to the widget's `workDirectory` setting, so
it persists across bar reloads and reboots. The widget reports when Vibe is not
installed or a configured directory cannot be accessed; it never installs
software or reads credentials on its own.

## Summon from a keybinding

The widget registers the IPC target `keis.vibe`, so you can open, close, or
toggle the panel from anywhere, for example:

```sh
qs -p /usr/share/omarchy/shell ipc call keis.vibe toggle
```

Bind that command in `~/.config/hypr/bindings.lua` to summon the launcher
with a keyboard shortcut. `ipc call keis.vibe pick` jumps straight to the
directory box; `ipc call keis.vibe state` prints the panel's current state
as JSON.

## Requirements

- Omarchy Quattro with the Quickshell plugin system.
- Mistral Vibe on your `PATH`. Install it using the
  [official Vibe instructions](https://github.com/mistralai/mistral-vibe#one-line-install-recommended)
  or, if you have `uv`, run `uv tool install mistral-vibe`.

Vibe handles its own account/API-key setup on first launch (`vibe --setup`
is also available). This plugin does not bypass Vibe's approval prompts.

## Install

From a public GitHub repository containing these files at its root:

```sh
omarchy plugin add https://github.com/anderskeis/keisVibe.git --enable
```

For a local copy of this directory under
`~/.config/omarchy/plugins/keis.vibe/`, run:

```sh
omarchy-shell shell rescanPlugins
omarchy plugin enable keis.vibe --section right
```

Reopen the panel after installing Vibe to update the availability indicator.
The plugin ID `keis.vibe` does not change your Omarchy default agent.
If a QML edit does not appear after a plugin rescan, run `omarchy restart shell`
to clear the shell's cached component.

## Configure the working directory

The default is `~/Work` when it exists, otherwise your home directory. To
start Vibe in a different folder, set `workDirectory` to an absolute path or
`~/path` (quote `~` to keep it from expanding in your shell):

```sh
omarchy bar set keis.vibe workDirectory '~/Projects/My Project'
```

The setting is stored with the widget in `~/.config/omarchy/shell.json`.
The chosen directory must already exist and be accessible; otherwise the
panel shows an error instead of launching. The directory box (`D`) edits this
same setting; setting it from the CLI pins a default without opening the
panel. Set it back to `~/Work` (or an empty string) to restore the default
Work-or-home behavior:

```sh
omarchy bar set keis.vibe workDirectory '~/Work'
```

## Validate and publish

```sh
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml
```

To list the plugin on [Omarchy Plugins](https://plugins.omarchy.org/publish.html),
publish these files at the root of the public GitHub repository above, then
submit its URL through the marketplace form. The marketplace validates
listings but does not sandbox plugins.

## Remove

```sh
omarchy plugin remove keis.vibe
```

Removing the widget does not remove Vibe or its sessions. This community
plugin is not affiliated with Mistral or Omarchy.
