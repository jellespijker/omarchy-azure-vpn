import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "azure-vpn"
  ipcTarget: "azure-vpn"

  readonly property string script: Quickshell.env("HOME") + "/.local/bin/azurevpn"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int barContentWidth: Style.bar.iconFont + Style.space(4)
  readonly property int barSlot: barContentWidth + Style.space(10)
  readonly property real openPanelIndicatorWidth: barContentWidth
  readonly property real openPanelIndicatorHeight: barContentWidth
  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  // VPN State
  property bool connected: false
  property string status: "disconnected"
  property string vpnIp: ""
  property var dnsServers: []
  property string gateway: ""
  property string account: ""
  property int uptimeSeconds: 0
  property string profile: "UM-AzureCloud"
  property string activeProfile: "UM-AzureCloud"
  property var availableProfiles: []
  property bool busy: false

  // Icons
  readonly property string iconVpn: "󰦝"
  readonly property string iconIp: "󰩠"
  readonly property string iconDns: "󰅣"
  readonly property string iconAccount: "󰀉"
  readonly property string iconServer: "󰒍"
  readonly property string iconPower: "󰐥"
  readonly property string iconImport: "󰏔"
  readonly property string iconCheck: "󰄬"
  readonly property string iconClock: "󱎫"

  function applyStatus(raw) {
    busy = false
    if (!raw || raw.trim() === "") return
    try {
      var data = JSON.parse(raw)
      root.connected = !!data.connected
      root.status = data.state || (root.connected ? "connected" : "disconnected")
      root.vpnIp = data.address || ""
      root.dnsServers = data.dnsServers || []
      root.gateway = data.gateway || ""
      root.account = data.account || ""
      root.uptimeSeconds = data.uptimeSeconds || 0
      root.profile = data.profile || data.active_profile || "Azure VPN"
      root.activeProfile = data.active_profile || root.profile
      root.availableProfiles = data.available_profiles || []
    } catch (e) {
      console.warn("Failed to parse Azure VPN status:", e, raw)
    }
  }

  function formatUptime(seconds) {
    if (!seconds || seconds <= 0) return "Just connected"
    var m = Math.floor(seconds / 60)
    var h = Math.floor(m / 60)
    var s = seconds % 60
    if (h > 0) return h + "h " + (m % 60) + "m"
    if (m > 0) return m + "m " + s + "s"
    return s + "s"
  }

  function refresh() {
    if (statusProc.running) return
    statusProc.command = [root.script, "status", "--json"]
    statusProc.running = true
  }

  function toggleConnection() {
    busy = true
    actionProc.command = [root.script, "toggle"]
    actionProc.running = true
  }

  function connectVpn() {
    busy = true
    actionProc.command = [root.script, "connect"]
    actionProc.running = true
  }

  function disconnectVpn() {
    busy = true
    actionProc.command = [root.script, "disconnect"]
    actionProc.running = true
  }

  function selectProfile(name) {
    busy = true
    selectProc.command = [root.script, "select", name]
    selectProc.running = true
  }

  function importProfile() {
    importProc.command = [root.script, "import-dialog"]
    importProc.running = true
  }

  // Background processes
  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: actionProc
    onExited: function(exitCode) {
      settleTimer.restart()
    }
  }

  Process {
    id: selectProc
    onExited: function(exitCode) {
      settleTimer.restart()
    }
  }

  Process {
    id: importProc
    onExited: function(exitCode) {
      settleTimer.restart()
    }
  }

  Timer {
    id: settleTimer
    interval: 500
    onTriggered: root.refresh()
  }

  // Polling timer: fast when popup is open or connecting, periodic when closed
  Timer {
    interval: root.opened ? 2000 : (root.status === "connecting" ? 1500 : 5000)
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  // Bar button representation
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconVpn
    slotSize: root.barSlot
    opticalSize: root.barContentWidth
    active: root.connected
    activeColor: root.accent
    useActiveColor: true
    tooltipText: root.connected 
      ? ("Azure VPN: " + root.profile + " (" + root.vpnIp + ")")
      : (root.status === "connecting" ? "Azure VPN: Connecting..." : "Azure VPN: Disconnected")

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.toggleConnection()
      } else if (b === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }
  }

  // Popout Panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: mainColumn
          width: parent.width
          spacing: Style.space(12)

          // Header Hero
          PanelHero {
            width: parent.width
            title: "Azure VPN"
            meta: root.connected ? "Connected" : (root.status === "connecting" ? "Connecting..." : "Disconnected")
            detail: root.profile
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.connected ? 1.0 : 0.6
            iconComponent: Component {
              Text {
                text: root.iconVpn
                font.family: root.fontFamily
                font.pixelSize: Style.space(22)
                color: root.connected ? root.accent : root.dim
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                checked: root.connected
                busy: root.busy
                accent: root.accent
                onToggled: root.toggleConnection()
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          // Profiles Selection Section
          Column {
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              width: parent.width
              PanelSectionHeader {
                Layout.fillWidth: true
                text: "PROFILES"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Button {
                text: "Import"
                iconText: root.iconImport
                fontFamily: root.fontFamily
                foreground: root.accent
                accent: root.accent
                bordered: false
                tooltipText: "Import an Azure VPN XML profile"
                onClicked: root.importProfile()
              }
            }

            // Profile list
            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.availableProfiles
                delegate: Rectangle {
                  id: profileRow
                  width: mainColumn.width
                  height: Style.space(36)
                  radius: Style.space(6)
                  color: (modelData === root.activeProfile) 
                    ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    : (rowMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent")

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(8)

                    Text {
                      text: (modelData === root.activeProfile) ? root.iconCheck : root.iconServer
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      color: (modelData === root.activeProfile) ? root.accent : root.dim
                    }

                    Text {
                      Layout.fillWidth: true
                      text: modelData
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      color: (modelData === root.activeProfile) ? root.foreground : root.dim
                      font.bold: (modelData === root.activeProfile)
                      elide: Text.ElideRight
                    }

                    Text {
                      visible: (modelData === root.activeProfile) && root.connected
                      text: "ACTIVE"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      color: root.accent
                      font.bold: true
                    }
                  }

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (modelData !== root.activeProfile) {
                        root.selectProfile(modelData)
                      }
                    }
                  }
                }
              }

              Text {
                visible: root.availableProfiles.length === 0
                text: "No profiles found. Click 'Import' to add one."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          // Active Connection Details
          Column {
            visible: root.connected
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "CONNECTION DETAILS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // IP Address Row
            Row {
              width: parent.width
              spacing: Style.space(10)
              Text {
                text: root.iconIp
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: root.dim
                width: Style.space(20)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }
              Column {
                spacing: Style.space(1)
                Text {
                  text: "Assigned IP"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
                Text {
                  text: root.vpnIp || "None"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  color: root.foreground
                  font.bold: true
                }
              }
            }

            // Account Row
            Row {
              visible: root.account !== ""
              width: parent.width
              spacing: Style.space(10)
              Text {
                text: root.iconAccount
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: root.dim
                width: Style.space(20)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }
              Column {
                spacing: Style.space(1)
                Text {
                  text: "Account"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
                Text {
                  text: root.account
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  color: root.foreground
                }
              }
            }

            // DNS Servers Row
            Row {
              visible: root.dnsServers.length > 0
              width: parent.width
              spacing: Style.space(10)
              Text {
                text: root.iconDns
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: root.dim
                width: Style.space(20)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }
              Column {
                spacing: Style.space(1)
                Text {
                  text: "DNS Servers"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
                Text {
                  text: root.dnsServers.join(", ")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  color: root.foreground
                }
              }
            }

            // Uptime Row
            Row {
              visible: root.uptimeSeconds > 0
              width: parent.width
              spacing: Style.space(10)
              Text {
                text: root.iconClock
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: root.dim
                width: Style.space(20)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }
              Column {
                spacing: Style.space(1)
                Text {
                  text: "Uptime"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
                Text {
                  text: root.formatUptime(root.uptimeSeconds)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  color: root.foreground
                }
              }
            }
          }

          // Disconnected description
          Text {
            visible: !root.connected && root.status !== "connecting"
            width: parent.width
            text: "Connect to Azure VPN directly in the background without any GUI client."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // Connecting description
          Text {
            visible: root.status === "connecting"
            width: parent.width
            text: "Establishing Azure VPN tunnel... (Browser will open automatically if authentication is required)."
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          // Primary Action Button
          Button {
            width: parent.width
            text: root.connected 
              ? "Disconnect" 
              : (root.status === "connecting" ? "Connecting..." : ("Connect to " + root.activeProfile))
            iconText: root.iconPower
            fontFamily: root.fontFamily
            foreground: root.connected ? root.urgent : root.foreground
            accent: root.connected ? root.urgent : root.accent
            bordered: true
            onClicked: root.toggleConnection()
          }
        }
      }
    }
  }
}
