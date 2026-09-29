import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "keis.vibe"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool availabilityChecked: false
  property bool vibeInstalled: false
  property int selectedIndex: 0
  property string launchError: ""
  property int pendingLaunchIndex: -1
  property string pendingDirectory: ""

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function refreshAvailability() {
    availabilityChecked = false
    launchError = ""
    if (!availabilityCheck.running) availabilityCheck.running = true
  }

  function open() {
    refreshAvailability()
    root.controller.show()
  }

  function close() {
    pendingLaunchIndex = -1
    pendingDirectory = ""
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function moveSelection(direction) {
    selectedIndex = (selectedIndex + direction + 3) % 3
  }

  function launch(index) {
    if (directoryCheck.running) return
    if (!availabilityChecked || !vibeInstalled) {
      launchError = "Vibe is not installed. Install it with: uv tool install mistral-vibe"
      return
    }

    var configured = root.setting("workDirectory", "~/Work")
    if (typeof configured !== "string") {
      launchError = "Working directory must be a path."
      return
    }

    var directory = ""
    if (configured !== "" && configured !== "~/Work") {
      directory = configured
      if (configured === "~" || configured.indexOf("~/") === 0) {
        var home = Quickshell.env("HOME")
        if (!home || home[0] !== "/") {
          launchError = "Cannot resolve your home directory."
          return
        }
        directory = configured === "~" ? home : home + configured.substring(1)
      } else if (configured[0] !== "/") {
        launchError = "Use an absolute path or ~/path for the working directory."
        return
      }
    }

    pendingLaunchIndex = index
    pendingDirectory = directory
    directoryCheck.command = [
      "bash", "-c",
      'dir="$1"; if [ -z "$dir" ]; then if [ -d "$HOME/Work" ]; then dir="$HOME/Work"; else dir="$HOME"; fi; fi; cd -- "$dir" 2>/dev/null',
      "vibe-directory-check", directory
    ]
    directoryCheck.running = true
  }

  function launchVibe(index, directory) {
    var args = index === 0 ? [] : index === 1 ? ["--continue"] : ["--resume"]
    var command = [
      "bash", "-lc",
      'dir="$1"; shift; if [ -z "$dir" ]; then if [ -d "$HOME/Work" ]; then dir="$HOME/Work"; else dir="$HOME"; fi; fi; cd -- "$dir" || exit 1; exec omarchy-launch-tui --app-id=org.omarchy.vibe vibe "$@"',
      "vibe-launcher", directory
    ].concat(args)
    Quickshell.execDetached(command)
    root.close()
  }

  Process {
    id: availabilityCheck
    command: ["bash", "-lc", "command -v vibe >/dev/null 2>&1"]
    onExited: function(exitCode) {
      root.vibeInstalled = exitCode === 0
      root.availabilityChecked = true
    }
  }

  Process {
    id: directoryCheck
    onExited: function(exitCode) {
      if (root.pendingLaunchIndex < 0) return
      var index = root.pendingLaunchIndex
      var directory = root.pendingDirectory
      root.pendingLaunchIndex = -1
      root.pendingDirectory = ""
      if (exitCode !== 0) {
        root.launchError = directory === ""
          ? "Cannot access ~/Work or your home directory."
          : "Cannot access working directory: " + root.setting("workDirectory", "~/Work")
        return
      }
      root.launchVibe(index, directory)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: root.launch(root.selectedIndex)
      onTextKey: function(text) {
        var key = text.toLowerCase()
        if (key === "n") root.launch(0)
        else if (key === "c") root.launch(1)
        else if (key === "r") root.launch(2)
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "MISTRAL VIBE"
          color: Color.accent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Your coding session, one click away."
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          opacity: 0.75
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Color.accent
          opacity: 0.45
        }

        Button {
          width: parent.width
          text: "New session"
          iconText: "\uf04b"
          leftAlign: true
          foreground: root.contentForeground
          hasCursor: root.selectedIndex === 0
          enabled: root.availabilityChecked && root.vibeInstalled && !directoryCheck.running
          onHovered: function(isHovered) { if (isHovered) root.selectedIndex = 0 }
          onClicked: root.launch(0)
        }

        Button {
          width: parent.width
          text: "Continue last session"
          iconText: "\uf0e2"
          leftAlign: true
          foreground: root.contentForeground
          hasCursor: root.selectedIndex === 1
          enabled: root.availabilityChecked && root.vibeInstalled && !directoryCheck.running
          onHovered: function(isHovered) { if (isHovered) root.selectedIndex = 1 }
          onClicked: root.launch(1)
        }

        Button {
          width: parent.width
          text: "Choose a session"
          iconText: "\uf0ca"
          leftAlign: true
          foreground: root.contentForeground
          hasCursor: root.selectedIndex === 2
          enabled: root.availabilityChecked && root.vibeInstalled && !directoryCheck.running
          onHovered: function(isHovered) { if (isHovered) root.selectedIndex = 2 }
          onClicked: root.launch(2)
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.launchError !== "" ? root.launchError
            : !root.availabilityChecked ? "Checking for Vibe..."
            : root.vibeInstalled ? "N New   C Last   R Pick   Tab Switch   Esc Close"
            : "Vibe not found. Install it with: uv tool install mistral-vibe"
          color: root.launchError !== "" ? Color.urgent : root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          opacity: root.launchError !== "" ? 1.0 : 0.75
        }
      }
    }
  }
}
