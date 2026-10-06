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
  property string agent: "vibe"
  // Left/Right cycles the picker through these in order.
  readonly property var agentOrder: ["vibe", "copilot", "agy"]
  property bool vibeChecked: false
  property bool copilotChecked: false
  property bool agyChecked: false
  readonly property bool availabilityChecked: vibeChecked && copilotChecked && agyChecked
  property bool vibeInstalled: false
  property bool copilotInstalled: false
  property bool agyInstalled: false
  property int selectedIndex: 0
  property string launchError: ""
  property int pendingLaunchIndex: -1
  property string pendingDirectory: ""
  property string pickedDirectory: ""
  property bool pickerMode: false
  property string dirError: ""
  property int completionSerial: 0

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string homePath: Quickshell.env("HOME") || ""

  function refreshAvailability() {
    vibeChecked = false
    copilotChecked = false
    agyChecked = false
    launchError = ""
    if (!vibeCheck.running) vibeCheck.running = true
    if (!copilotCheck.running) copilotCheck.running = true
    if (!agyCheck.running) agyCheck.running = true
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

  function moveSelection(direction) {
    selectedIndex = (selectedIndex + direction + 4) % 4
  }

  function agentInstalled() {
    if (agent === "copilot") return copilotInstalled
    if (agent === "agy") return agyInstalled
    return vibeInstalled
  }

  function agentMissingHint() {
    if (agent === "copilot")
      return "Copilot not found. Get it from: github.com/github/copilot-cli/releases"
    if (agent === "agy")
      return "Agy not found. Install it with: curl -fsSL https://antigravity.google/cli/install.sh | bash"
    return "Vibe not found. Install it with: uv tool install mistral-vibe"
  }

  function selectAgent(nextAgent) {
    if (agent === nextAgent) return
    agent = nextAgent
    launchError = ""
  }

  function cycleAgent(direction) {
    var count = agentOrder.length
    var index = agentOrder.indexOf(agent)
    if (index < 0) index = 0
    selectAgent(agentOrder[((index + direction) % count + count) % count])
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
    if (!availabilityChecked || !agentInstalled()) {
      launchError = agentMissingHint()
      return
    }
    // Agy has no launch-time session picker; its /resume picker only works
    // as a slash command inside a running session.
    if (agent === "agy" && index === 2) {
      launchError = "Agy chooses sessions with /resume inside a session."
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

  function launchAgent(index, directory) {
    var agentCommand = agent === "copilot" ? "copilot" : agent === "agy" ? "agy" : "vibe"
    var agentAppId = agent === "copilot"
      ? "org.omarchy.copilot"
      : agent === "agy" ? "org.omarchy.agy" : "org.omarchy.vibe"
    var args = index === 0 ? [] : index === 1 ? ["--continue"] : ["--resume"]
    var command = [
      "bash", "-lc",
      'dir="$1"; shift; if [ -z "$dir" ]; then if [ -d "$HOME/Work" ]; then dir="$HOME/Work"; else dir="$HOME"; fi; fi; cd -- "$dir" || exit 1; exec omarchy-launch-tui --app-id=' + agentAppId + ' ' + agentCommand + ' "$@"',
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
    // The field keeps activeFocus when the box hides, which would leave
    // main-panel keys dead. Hand focus back to the panel key catcher.
    Qt.callLater(function() {
      if (!pickerMode && keyCatcher) keyCatcher.forceActiveFocus()
    })
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

  // Shell-style Tab completion for the directory box. Completes the last
  // path segment against the subdirectories of the segment before it:
  // a unique match completes fully with a trailing slash, several matches
  // extend to their longest common prefix, and nothing happens when the
  // typed text cannot be extended. Matching is case-insensitive but always
  // inserts real-case names. Hidden folders are never offered. Tab on an
  // empty field starts from ~.
  function requestCompletion() {
    if (completionProc.running) return
    var text = dirField.text
    if (text.trim() === "" || text === "~") {
      dirField.text = "~/"
      dirField.cursorPosition = dirField.text.length
      return
    }
    var slash = text.lastIndexOf("/")
    if (slash < 0) return
    var dirPart = text.substring(0, slash + 1)
    var prefix = text.substring(slash + 1)
    var expanded = expandDirPart(dirPart)
    if (expanded === "") return
    completionSerial += 1
    completionProc.activeSerial = completionSerial
    completionProc.dirPart = dirPart
    completionProc.prefix = prefix
    completionProc.command = [
      "bash", "-c",
      'find "$1" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -5000 | LC_ALL=C sort',
      "vibe-directory-complete", expanded
    ]
    completionProc.running = true
  }

  function expandDirPart(dirPart) {
    if (dirPart.indexOf("~/") === 0) return homePath + dirPart.substring(1)
    if (dirPart[0] === "/") return dirPart
    return ""
  }

  function commonPrefix(names) {
    var prefix = names[0]
    for (var i = 1; i < names.length; i++) {
      var next = names[i]
      var j = 0
      while (j < prefix.length && j < next.length && prefix[j] === next[j]) j++
      prefix = prefix.substring(0, j)
    }
    return prefix
  }

  function applyCompletion(dirPart, prefix, matches) {
    var wanted = prefix.toLowerCase()
    var realNames = []
    for (var i = 0; i < matches.length; i++) {
      var name = matches[i]
      if (name.indexOf("/") >= 0) name = name.substring(name.lastIndexOf("/") + 1)
      if (name.length === 0 || name[0] === ".") continue
      if (name.toLowerCase().indexOf(wanted) !== 0) continue
      realNames.push(name)
    }
    if (realNames.length === 0) return
    var completed = realNames.length === 1
      ? realNames[0]
      : commonPrefix(realNames)
    if (completed === prefix || completed === "") return
    dirField.text = dirPart + completed + (realNames.length === 1 ? "/" : "")
    dirField.cursorPosition = dirField.text.length
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
      agent: root.agent,
      pickerMode: pickerMode,
      dirError: dirError,
      pickedDirectory: pickedDirectory,
      dirText: pickerMode ? dirField.text : "",
      selectedIndex: selectedIndex,
      workDirectory: root.setting("workDirectory", "~/Work")
    })
  }

  Process {
    id: vibeCheck
    command: ["bash", "-lc", "command -v vibe >/dev/null 2>&1"]
    onExited: function(exitCode) {
      root.vibeInstalled = exitCode === 0
      root.vibeChecked = true
    }
  }

  Process {
    id: copilotCheck
    command: ["bash", "-lc", "command -v copilot >/dev/null 2>&1"]
    onExited: function(exitCode) {
      root.copilotInstalled = exitCode === 0
      root.copilotChecked = true
    }
  }

  Process {
    id: agyCheck
    command: ["bash", "-lc", "command -v agy >/dev/null 2>&1"]
    onExited: function(exitCode) {
      root.agyInstalled = exitCode === 0
      root.agyChecked = true
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
      root.launchAgent(index, directory)
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

  Process {
    id: completionProc
    property int activeSerial: 0
    property string dirPart: ""
    property string prefix: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (completionProc.activeSerial !== root.completionSerial) return
        if (!root.pickerMode) return
        var lines = String(text || "").split("\n")
        while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
        root.applyCompletion(completionProc.dirPart, completionProc.prefix, lines)
      }
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
      onMoveRequested: function(dx, dy) {
        if (root.pickerMode) return
        if (dy !== 0) root.moveSelection(dy)
        else if (dx !== 0) root.cycleAgent(dx > 0 ? 1 : -1)
      }
      onActivateRequested: if (!root.pickerMode) root.launch(root.selectedIndex)
      onTextKey: function(text) {
        if (root.pickerMode) return
        var key = text.toLowerCase()
        if (key === "n") root.launch(0)
        else if (key === "c") root.launch(1)
        else if (key === "r") root.launch(2)
        else if (key === "d") root.openPicker()
        else if (key === "v") root.selectAgent("vibe")
        else if (key === "g") root.selectAgent("copilot")
        else if (key === "a") root.selectAgent("agy")
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !root.pickerMode

          ButtonGroup {
            width: parent.width
            value: root.agent
            options: [
              { value: "vibe", label: "Vibe" },
              { value: "copilot", label: "GH Copilot" },
              { value: "agy", label: "Agy" }
            ]
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onChanged: function(value) { root.selectAgent(value) }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.agent === "copilot" ? "GITHUB COPILOT"
              : root.agent === "agy" ? "ANTIGRAVITY"
              : "MISTRAL VIBE"
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
            enabled: root.availabilityChecked && root.agentInstalled() && !directoryCheck.running
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
            enabled: root.availabilityChecked && root.agentInstalled() && !directoryCheck.running
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
            enabled: root.availabilityChecked && root.agentInstalled()
              && root.agent !== "agy" && !directoryCheck.running
            tooltipText: root.agent === "agy"
              ? "Agy picks sessions with /resume inside a running session."
              : ""
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
            text: "Where sessions start."
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
            Keys.onTabPressed: root.requestCompletion()
            onAccepted: root.confirmDirectory(text)
            onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
          }

          Button {
            width: parent.width
            text: "Reset to default (~/Work or home)"
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
            ? (root.dirError !== "" ? root.dirError : "Enter Confirm   Tab Complete   Esc Cancel")
            : root.launchError !== "" ? root.launchError
            : !root.availabilityChecked ? "Checking for agents..."
            : root.agentInstalled() ? "↑↓ Move   ←→ Agent   Esc Close"
            : root.agentMissingHint()
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
