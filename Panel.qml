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
  property string browsePath: ""
  property var browseEntries: []
  property int browseIndex: 0
  property int browseSerial: 0
  property string browseError: ""

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string homePath: Quickshell.env("HOME") || ""
  readonly property bool browseHasParent: browsePath !== "" && browsePath !== "/"
  readonly property int browseEntryOffset: browseHasParent ? 2 : 1
  readonly property int browseRowCount: browseEntryOffset + browseEntries.length

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
    closePicker()
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

  function parentOf(path) {
    if (path === "" || path === "/") return ""
    var idx = path.lastIndexOf("/")
    if (idx <= 0) return "/"
    return path.substring(0, idx)
  }

  function shorten(text, max) {
    return text.length <= max ? text : "..." + text.substring(text.length - max + 1)
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

  function browseStartPath() {
    if (pickedDirectory !== "") return pickedDirectory
    var resolved = resolveConfiguredDirectory()
    return resolved.indexOf("error:") === 0 ? "" : resolved
  }

  function openPicker() {
    browseError = ""
    pickerMode = true
    browseDirectory("")
  }

  function closePicker() {
    pickerMode = false
    browseSerial += 1
    browseProc.activeSerial = 0
    browsePath = ""
    browseEntries = []
    browseIndex = 0
  }

  function browseDirectory(path) {
    browseError = ""
    browseEntries = []
    browseIndex = 0
    var serial = root.browseSerial + 1
    root.browseSerial = serial
    if (browseProc.running) {
      browseProc.queuedSerial = serial
      browseProc.queuedPath = path
      return
    }
    startBrowse(serial, path)
  }

  function startBrowse(serial, path) {
    browseProc.activeSerial = serial
    browseProc.command = [
      "bash", "-c",
      'start="$1"; configured="$2"; if [ -z "$start" ]; then if [ -n "$configured" ] && [ -d "$configured" ]; then start="$configured"; elif [ -d "$HOME/Work" ]; then start="$HOME/Work"; else start="$HOME"; fi; fi; echo "$start"; find "$start" -mindepth 1 -maxdepth 1 -type d ! -name ".*" 2>/dev/null | LC_ALL=C sort',
      "vibe-directory-browse", path, browseStartPath()
    ]
    browseProc.running = true
  }

  function pickerMove(direction) {
    if (browseRowCount === 0) return
    browseIndex = (browseIndex + direction + browseRowCount) % browseRowCount
  }

  function pickerActivate(row) {
    if (!pickerMode) return
    if (row === 0) {
      if (browsePath === "") return
      pickedDirectory = browsePath
      launchError = ""
      closePicker()
      return
    }
    if (browseHasParent && row === 1) {
      browseDirectory(parentOf(browsePath))
      return
    }
    var i = row - browseEntryOffset
    if (i >= 0 && i < browseEntries.length) browseDirectory(browseEntries[i])
  }

  function pickerNavigate(dx) {
    if (dx < 0 && browseHasParent) browseDirectory(parentOf(browsePath))
    else if (dx > 0) pickerActivate(browseIndex)
  }

  function pickerEntryName(path) {
    var idx = path.lastIndexOf("/")
    return idx >= 0 ? path.substring(idx + 1) : path
  }

  function clearPickedDirectory() {
    if (pickedDirectory === "") return
    pickedDirectory = ""
    launchError = ""
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
    id: browseProc
    property int activeSerial: 0
    property int queuedSerial: 0
    property string queuedPath: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (browseProc.activeSerial !== root.browseSerial) return
        var lines = String(text || "").split("\n")
        while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
        if (lines.length === 0) {
          root.browseError = "Cannot browse directories."
          return
        }
        root.browsePath = lines[0]
        var entries = []
        for (var i = 1; i < lines.length; i++) entries.push(lines[i])
        root.browseEntries = entries
        root.browseIndex = 0
      }
    }
    onExited: function(exitCode) {
      var serial = browseProc.queuedSerial
      var path = browseProc.queuedPath
      browseProc.activeSerial = 0
      browseProc.queuedSerial = 0
      browseProc.queuedPath = ""
      if (serial > 0 && serial === root.browseSerial)
        root.startBrowse(serial, path)
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
      onCloseRequested: if (root.pickerMode) root.closePicker(); else root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.pickerMode) {
          if (dy !== 0) root.pickerMove(dy)
          else if (dx !== 0) root.pickerNavigate(dx)
        } else if (dy !== 0) {
          root.moveSelection(dy)
        }
      }
      onActivateRequested: if (root.pickerMode) root.pickerActivate(root.browseIndex); else root.launch(root.selectedIndex)
      onDeleteRequested: if (!root.pickerMode) root.clearPickedDirectory()
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
            text: root.shorten("Directory: " + root.displayDirectory(), 40)
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
            text: "CHOOSE DIRECTORY"
            color: Color.accent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.browseError !== "" ? root.browseError
              : root.browsePath === "" ? "Loading..."
              : root.shorten(root.tildePath(root.browsePath), 42)
            color: root.browseError !== "" ? Color.urgent : root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            opacity: root.browseError !== "" ? 1.0 : 0.75
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Color.accent
            opacity: 0.45
          }

          Button {
            width: parent.width
            text: "Use this directory"
            iconText: "\uf00c"
            leftAlign: true
            fontSize: Style.font.bodySmall
            foreground: root.contentForeground
            hasCursor: root.browseIndex === 0
            enabled: root.browsePath !== "" && root.browseError === ""
            onHovered: function(isHovered) { if (isHovered) root.browseIndex = 0 }
            onClicked: root.pickerActivate(0)
          }

          Button {
            width: parent.width
            visible: root.browseHasParent
            text: ".."
            iconText: "\uf062"
            leftAlign: true
            fontSize: Style.font.bodySmall
            foreground: root.contentForeground
            hasCursor: root.browseHasParent && root.browseIndex === 1
            onHovered: function(isHovered) { if (isHovered && root.browseHasParent) root.browseIndex = 1 }
            onClicked: if (root.browseHasParent) root.pickerActivate(1)
          }

          Repeater {
            model: root.browseEntries.length

            Button {
              id: entryButton
              required property int index
              width: parent.width
              text: root.shorten(root.pickerEntryName(root.browseEntries[index]), 30)
              iconText: "\uf07b"
              leftAlign: true
              fontSize: Style.font.bodySmall
              foreground: root.contentForeground
              hasCursor: root.browseIndex === root.browseEntryOffset + index
              onHovered: function(isHovered) {
                if (isHovered) root.browseIndex = root.browseEntryOffset + index
              }
              onClicked: root.pickerActivate(root.browseEntryOffset + index)
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.browseError === "" && root.browsePath !== "" && root.browseEntries.length === 0
            text: "No subdirectories."
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            opacity: 0.5
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.pickerMode
            ? "Enter Select   \u2192 Open   \u2190 Up   Esc Back"
            : root.launchError !== "" ? root.launchError
            : !root.availabilityChecked ? "Checking for Vibe..."
            : root.vibeInstalled ? "N New   C Last   R Pick   D Dir   X Reset   Tab Switch   Esc Close"
            : "Vibe not found. Install it with: uv tool install mistral-vibe"
          color: root.launchError !== "" && !root.pickerMode ? Color.urgent : root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          opacity: root.launchError !== "" && !root.pickerMode ? 1.0 : 0.75
        }
      }
    }
  }
}
