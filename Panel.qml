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
  property string pickedDirectory: ""
  property bool pickerMode: false
  property string dirError: ""

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string homePath: Quickshell.env("HOME") || ""

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
    pickerMode = false
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
    selectedIndex = (selectedIndex + direction + 4) % 4
  }

  function tildePath(path) {
    return homePath !== "" && path.indexOf(homePath) === 0
      ? "~" + path.substring(homePath.length)
      : path
  }

  function shorten(text, max) {
    if (text.length <= max) return text
    return text.substring(0, Math.max(1, max - 10)) + "..." + text.substring(text.length - 6)
  }

  function displayDirectory() {
    if (pickedDirectory !== "") return tildePath(pickedDirectory)
    var configured = root.setting("workDirectory", "~/Work")
    if (typeof configured === "string" && configured !== "" && configured !== "~/Work")
      return configured
    return "~/Work (default)"
  }

  // Returns an absolute path, "" for the default Work-or-home fallback, or
  // "error:" + message when the configured working directory is unusable.
  function resolveConfiguredDirectory() {
    var configured = root.setting("workDirectory", "~/Work")
    if (typeof configured !== "string") return "error:Working directory must be a path."
    if (configured === "" || configured === "~/Work") return ""
    if (configured === "~" || configured.indexOf("~/") === 0) {
      if (homePath === "" || homePath[0] !== "/")
        return "error:Cannot resolve your home directory."
      return configured === "~" ? homePath : homePath + configured.substring(1)
    }
    if (configured[0] === "/") return configured
    return "error:Use an absolute path or ~/path for the working directory."
  }

  function launch(index) {
    if (directoryCheck.running) return
    if (!availabilityChecked || !vibeInstalled) {
      launchError = "Vibe is not installed. Install it with: uv tool install mistral-vibe"
      return
    }

    var directory = ""
    if (pickedDirectory !== "") {
      directory = pickedDirectory
    } else {
      var resolved = resolveConfiguredDirectory()
      if (resolved.indexOf("error:") === 0) {
        launchError = resolved.substring(6)
        return
      }
      directory = resolved
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

  function directoryPrefill() {
    if (pickedDirectory !== "") return tildePath(pickedDirectory)
    var configured = root.setting("workDirectory", "~/Work")
    return typeof configured === "string" && configured !== "" ? configured : "~/Work"
  }

  function openPicker() {
    if (!root.opened) root.open()
    dirError = ""
    dirField.text = directoryPrefill()
    pickerMode = true
  }

  function closePicker() {
    dirError = ""
    pickerMode = false
  }

  // Accepts a typed path, expands ~, validates accessibility, then uses and
  // persists it. Empty input is an error; "Reset to default" clears instead.
  function confirmDirectory(input) {
    if (dirValidate.running) return
    dirError = ""
    var text = String(input || "").trim()
    if (text === "") {
      dirError = "Enter a path like ~/Projects or /home/you/Projects."
      return
    }
    var directory = ""
    if (text === "~") directory = homePath
    else if (text.indexOf("~/") === 0) directory = homePath + text.substring(1)
    else if (text[0] === "/") directory = text
    else {
      dirError = "Use an absolute path or ~/path."
      return
    }
    if (directory === "") {
      dirError = "Cannot resolve your home directory."
      return
    }
    dirValidate.pendingPath = directory
    dirValidate.command = [
      "bash", "-c",
      'test -d "$1" && test -r "$1" && test -x "$1"',
      "vibe-directory-validate", directory
    ]
    dirValidate.running = true
  }

  function resetDirectory() {
    pickedDirectory = ""
    launchError = ""
    dirError = ""
    persistWorkDirectory("~/Work")
    closePicker()
  }

  // Persist a workDirectory choice through the shell's setBarWidget IPC.
  // Settings-only changes patch the running widget in place, so the panel
  // stays open and root.setting("workDirectory") reflects the new value.
  // pickedDirectory mirrors it until that update lands. A write issued while
  // one is in flight queues as the latest value instead of being dropped,
  // so a quick pick followed by a reset still ends at the reset value.
  function persistWorkDirectory(value) {
    if (persistProc.running) {
      persistProc.queuedValue = value
      return
    }
    startPersistWorkDirectory(value)
  }

  function startPersistWorkDirectory(value) {
    persistProc.command = [
      "omarchy-shell", "-q", "shell", "setBarWidget", root.moduleName,
      "workDirectory", JSON.stringify(value), "{}"
    ]
    persistProc.running = true
  }

  // Exposed through the keis.vibe IPC target for keybindings and debugging.
  function debugState(): string {
    return JSON.stringify({
      opened: root.opened,
      pickerMode: pickerMode,
      dirError: dirError,
      pickedDirectory: pickedDirectory,
      selectedIndex: selectedIndex,
      workDirectory: root.setting("workDirectory", "~/Work")
    })
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
          : "Cannot access working directory: " + root.tildePath(directory)
        return
      }
      root.launchVibe(index, directory)
    }
  }

  Process {
    id: dirValidate
    property string pendingPath: ""
    onExited: function(exitCode) {
      if (pendingPath === "") return
      var directory = pendingPath
      pendingPath = ""
      if (exitCode !== 0) {
        root.dirError = "Not an accessible directory: " + root.tildePath(directory)
        return
      }
      root.pickedDirectory = directory
      root.launchError = ""
      root.persistWorkDirectory(directory)
      root.closePicker()
    }
  }

  Process {
    id: persistProc
    property string queuedValue: ""
    onExited: function(exitCode) {
      if (queuedValue === "") return
      var value = queuedValue
      queuedValue = ""
      root.startPersistWorkDirectory(value)
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
      // The directory box owns input while it is open; its TextField handles
      // Enter (confirm) and Esc (cancel) itself.
      blocked: root.pickerMode
      onCloseRequested: if (root.pickerMode) root.closePicker(); else root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.pickerMode) return
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: if (!root.pickerMode) root.launch(root.selectedIndex)
      onDeleteRequested: if (!root.pickerMode) root.resetDirectory()
      onTextKey: function(text) {
        if (root.pickerMode) return
        var key = text.toLowerCase()
        if (key === "n") root.launch(0)
        else if (key === "c") root.launch(1)
        else if (key === "r") root.launch(2)
        else if (key === "d") root.openPicker()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !root.pickerMode

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

          Button {
            width: parent.width
            text: root.shorten("Directory: " + root.displayDirectory(), 34)
            iconText: root.pickedDirectory !== "" ? "\uf07c" : "\uf07b"
            leftAlign: true
            fontSize: Style.font.bodySmall
            foreground: root.contentForeground
            hasCursor: root.selectedIndex === 3
            onHovered: function(isHovered) { if (isHovered) root.selectedIndex = 3 }
            onClicked: root.openPicker()
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.pickerMode

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "WORKING DIRECTORY"
            color: Color.accent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Where Vibe sessions start. The choice is saved to the workDirectory setting."
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            opacity: 0.75
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Color.accent
            opacity: 0.45
          }

          TextField {
            id: dirField
            width: parent.width
            placeholderText: "~/Projects"
            text: ""
            font.family: root.contentFontFamily
            foreground: root.contentForeground
            Keys.onEscapePressed: root.closePicker()
            onAccepted: root.confirmDirectory(text)
            onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
          }

          Button {
            width: parent.width
            text: "Use this directory"
            iconText: "\uf00c"
            leftAlign: true
            fontSize: Style.font.bodySmall
            foreground: root.contentForeground
            onClicked: root.confirmDirectory(dirField.text)
          }

          Button {
            width: parent.width
            text: "Reset to default (~Work or home)"
            iconText: "\uf0e2"
            leftAlign: true
            fontSize: Style.font.bodySmall
            foreground: root.contentForeground
            onClicked: root.resetDirectory()
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.pickerMode
            ? (root.dirError !== "" ? root.dirError : "Enter Confirm   Esc Cancel")
            : root.launchError !== "" ? root.launchError
            : !root.availabilityChecked ? "Checking for Vibe..."
            : root.vibeInstalled ? "N New   C Last   R Pick   D Dir   X Reset   Tab Switch   Esc Close"
            : "Vibe not found. Install it with: uv tool install mistral-vibe"
          color: root.dirError !== "" && root.pickerMode
            ? Color.urgent
            : root.launchError !== "" && !root.pickerMode ? Color.urgent : root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          opacity: root.dirError !== "" && root.pickerMode
            ? 1.0
            : root.launchError !== "" && !root.pickerMode ? 1.0 : 0.75
        }
      }
    }
  }
}
