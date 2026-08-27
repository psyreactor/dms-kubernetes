import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "kubernetes"

    property string currentContext: "..."
    property var availableContexts: []
    property bool loading: true
    // Bumped on every fetchKubeContext() so callbacks from an abandoned cycle
    // (watchdog timeout, overlapping refresh) can be discarded instead of
    // completing it.
    property int refreshEpoch: 0
    property bool hasError: false
    property string errorMessage: ""
    
    // Settings
    property string kubeconfigPath: pluginData.kubeconfigPath || "~/.kube/config"
    property int refreshInterval: pluginData.refreshInterval || 300
    property bool hideContextName: pluginData.hideContextName || false
    property bool popoutOpen: false

    readonly property string displayContext: root.hasError
        ? "Error"
        : (root.currentContext !== "..." && root.currentContext.length > 0 ? root.currentContext : "...")

    // Extra top gap for vertical bars that don't span the full screen height.
    readonly property real minTooltipY: (root.isVertical && root.parentScreen && root.parentScreen.y > 0)
        ? (root.barThickness + root.barSpacing) : 0

    // Bar tooltip via DankTooltip (own overlay PanelWindow, positioned outside the bar strip in
    // screen coordinates) so it never overlaps the pill — mirrors the native Vpn/DiskUsage widgets.
    function showBarTooltip(loader, anchorItem) {
        if (!root.parentScreen || root.popoutOpen)
            return
        loader.active = true
        if (!loader.item)
            return
        const scr = root.parentScreen
        const text = root.displayContext
        if (root.isVertical) {
            const p = anchorItem.mapToItem(null, anchorItem.width / 2, anchorItem.height / 2)
            const isLeft = root.axis?.edge === "left"
            const x = isLeft ? (root.barThickness + root.barSpacing + Theme.spacingXS)
                             : (scr.width - root.barThickness - root.barSpacing - Theme.spacingXS)
            loader.item.show(text, x, p.y + root.minTooltipY, scr, isLeft, !isLeft)
        } else {
            const isBottom = root.axis?.edge === "bottom"
            const p = anchorItem.mapToItem(null, anchorItem.width / 2, 0)
            const th = Theme.fontSizeSmall * 1.5 + Theme.spacingS * 2
            const y = isBottom ? (scr.height - root.barThickness - root.barSpacing - Theme.spacingXS - th)
                               : (root.barThickness + root.barSpacing + Theme.spacingXS)
            loader.item.show(text, p.x, y, scr, false, false)
        }
    }

    function hideBarTooltip(loader) {
        if (loader.item)
            loader.item.hide()
        loader.active = false
    }

    Timer {
        interval: root.refreshInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchKubeContext()
    }

    // If a Proc callback never fires, `loading` would latch true forever and the
    // popout would spin on "Loading contexts..." for the rest of the session.
    // 30s is above the worst legitimate case: currentContext and allContexts are
    // chained and carry a 10s Proc timeout each.
    Timer {
        id: loadingWatchdog
        interval: 30000
        repeat: false
        running: root.loading
        onTriggered: {
            root.refreshEpoch++
            root.loading = false
            root.hasError = true
            root.errorMessage = "Timed out talking to kubectl. Will retry."
        }
    }

    // Proc.runCommand() is a singleton that keeps one entry per id and reads
    // entry.callback at completion time, so two widget instances (one per
    // bar/monitor) sharing an id clobber each other and only the last one
    // registered ever fires. A null id makes Proc mint a private id per call and
    // drop the entry once it completes.

    function fetchKubeContext() {
        root.loading = true
        const gen = ++root.refreshEpoch
        const expandedPath = root.kubeconfigPath.replace(/^~/, Quickshell.env("HOME"))

        Proc.runCommand(null, ["kubectl", "--kubeconfig", expandedPath, "config", "current-context"], (stdout, exitCode) => {
            if (gen !== root.refreshEpoch)
                return

            if (exitCode === 0) {
                root.currentContext = stdout.trim()
                root.hasError = false
                fetchAllContexts(gen)
            } else {
                root.hasError = true
                root.errorMessage = "Error: kubectl not found or invalid config"
                root.currentContext = "N/A"
            }
            root.loading = false
        }, 0, 10000)
    }

    function fetchAllContexts(gen) {
        const expandedPath = root.kubeconfigPath.replace(/^~/, Quickshell.env("HOME"))

        Proc.runCommand(null, ["kubectl", "--kubeconfig", expandedPath, "config", "get-contexts", "-o", "name"], (stdout, exitCode) => {
            if (gen !== root.refreshEpoch)
                return

            if (exitCode === 0) {
                root.availableContexts = stdout.trim().split("\n").filter(ctx => ctx.length > 0)
            } else {
                root.availableContexts = []
            }
        }, 0, 10000)
    }

    // No epoch guard here: this is a user action, not part of a refresh cycle,
    // and fetchKubeContext() bumps the epoch, so any generation captured here
    // would read as stale by the time the callback lands.
    function switchContext(contextName) {
        const expandedPath = root.kubeconfigPath.replace(/^~/, Quickshell.env("HOME"))

        Proc.runCommand(null, ["kubectl", "--kubeconfig", expandedPath, "config", "use-context", contextName], (stdout, exitCode) => {
            if (exitCode === 0) {
                fetchKubeContext()
            }
        }, 0, 10000)
    }



    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankSVGIcon {
                id: pillIcon
                source: Qt.resolvedUrl("kubernetes.svg")
                size: Theme.iconSize - 4
                colorOverride: root.hasError ? Theme.error : (Theme.widgetIconColor || Theme.surfaceText)
                anchors.verticalCenter: parent.verticalCenter

                property bool wantTooltip: iconHover.hovered && root.hideContextName && !root.popoutOpen
                onWantTooltipChanged: wantTooltip
                    ? root.showBarTooltip(tooltipLoader, pillIcon)
                    : root.hideBarTooltip(tooltipLoader)

                HoverHandler {
                    id: iconHover
                }

                Loader {
                    id: tooltipLoader
                    active: false
                    sourceComponent: DankTooltip {}
                }
            }

            StyledText {
                visible: !root.hideContextName
                text: root.displayContext
                color: root.hasError ? Theme.error : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            DankSVGIcon {
                id: pillIconVertical
                source: Qt.resolvedUrl("kubernetes.svg")
                size: 24
                colorOverride: root.hasError ? Theme.error : (Theme.widgetIconColor || Theme.surfaceText)
                anchors.horizontalCenter: parent.horizontalCenter

                // Vertical bar never renders the context name (looks bad); reveal it on hover only.
                property bool wantTooltip: iconHoverVertical.hovered && !root.popoutOpen
                onWantTooltipChanged: wantTooltip
                    ? root.showBarTooltip(tooltipLoaderVertical, pillIconVertical)
                    : root.hideBarTooltip(tooltipLoaderVertical)

                HoverHandler {
                    id: iconHoverVertical
                }

                Loader {
                    id: tooltipLoaderVertical
                    active: false
                    sourceComponent: DankTooltip {}
                }
            }
        }
    }

    component ContextItem: Item {
        property string contextName: ""
        readonly property bool isCurrent: contextName === root.currentContext

        width: ListView.view.width
        height: 40

        scale: itemArea.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: 100 } }

        MouseArea {
            id: itemArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => itemRipple.trigger(mouse.x, mouse.y)
            onClicked: {
                if (!isCurrent) {
                    root.switchContext(contextName)
                    root.closePopout()
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Theme.cornerRadius
            color: isCurrent
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                   : (itemArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : "transparent")
            border.width: isCurrent ? 1 : 0
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
        }

        DankRipple { id: itemRipple; rippleColor: Theme.primary; cornerRadius: Theme.cornerRadius }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                name: isCurrent ? "check_circle" : "radio_button_unchecked"
                size: 18
                color: isCurrent ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                width: parent.width - 30
                text: contextName
                font.pixelSize: Theme.fontSizeSmall
                font.weight: isCurrent ? Font.Bold : Font.Normal
                color: Theme.surfaceText
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    popoutContent: Component {
        Column {
            id: popoutColumn
            width: parent.width
            spacing: Theme.spacingM
            topPadding: Theme.spacingM
            bottomPadding: Theme.spacingM

            // Injected by PluginPopout; used to hide the bar tooltip while the popout is open.
            property var parentPopout: null
            onParentPopoutChanged: if (parentPopout) root.popoutOpen = parentPopout.shouldBeVisible

            Connections {
                target: popoutColumn.parentPopout
                ignoreUnknownSignals: true
                function onShouldBeVisibleChanged() {
                    root.popoutOpen = popoutColumn.parentPopout.shouldBeVisible
                }
            }

            Component.onDestruction: root.popoutOpen = false

            // Header card
            Item {
                id: headerCard
                width: parent.width
                height: 68

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.cornerRadius * 1.5
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) }
                        GradientStop { position: 1.0; color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08) }
                    }
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    DankSVGIcon {
                        source: Qt.resolvedUrl("kubernetes.svg")
                        size: 32
                        colorOverride: root.hasError ? Theme.error : Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        width: headerCard.width - 32 - 38 - Theme.spacingM * 4

                        StyledText {
                            width: parent.width
                            text: "Kubernetes"
                            font.bold: true
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: root.hasError
                                  ? "Error"
                                  : (root.currentContext !== "..." && root.currentContext.length > 0
                                      ? "Current: " + root.currentContext
                                      : "Loading current context...")
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.hasError ? Theme.error : Theme.surfaceVariantText
                            elide: Text.ElideRight
                        }
                    }
                }

                // Translucent refresh button
                Item {
                    width: 38
                    height: 38
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    scale: refreshArea.pressed ? 0.9 : (refreshArea.containsMouse ? 1.1 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => refreshRipple.trigger(mouse.x, mouse.y)
                        onClicked: root.fetchKubeContext()
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: refreshArea.containsMouse
                               ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                               : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.4)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, refreshArea.containsMouse ? 0.3 : 0.15)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    DankIcon {
                        id: refreshIcon
                        name: "refresh"
                        size: 20
                        color: Theme.primary
                        anchors.centerIn: parent

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                            running: root.loading
                        }
                    }

                    DankRipple {
                        id: refreshRipple
                        rippleColor: Theme.surfaceText
                        cornerRadius: Theme.cornerRadius
                        anchors.fill: parent
                    }
                }
            }

            // Error card
            StyledRect {
                width: parent.width
                height: root.hasError ? 60 : 0
                radius: Theme.cornerRadius
                color: Theme.errorContainer
                visible: root.hasError

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingL * 2
                    text: root.errorMessage
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.onErrorContainer
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            // Contexts section header
            Item {
                width: parent.width
                height: 32
                visible: !root.hasError

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 4
                        height: 22
                        radius: 2
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "lan"
                        size: 20
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Contexts"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: countBadge.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: countBadge
                            text: root.availableContexts.length.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }
                }
            }

            // Contexts list container
            StyledRect {
                width: parent.width
                height: root.loading
                        ? 54
                        : (root.availableContexts.length > 0
                            ? Math.min(root.availableContexts.length * 40 + (root.availableContexts.length - 1) * 6 + 28, 360)
                            : 54)
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                visible: !root.hasError
                clip: true

                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                // Loading state
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.loading

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                        RotationAnimation on rotation {
                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: parent.visible
                        }
                    }
                    StyledText {
                        text: "Loading contexts..."
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Empty state
                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.loading && root.availableContexts.length === 0

                    DankIcon { name: "info"; size: 16; color: Theme.secondary; anchors.verticalCenter: parent.verticalCenter }
                    StyledText {
                        text: "No contexts found"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.topMargin: 14
                    anchors.bottomMargin: 14
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingS
                    spacing: 6
                    model: root.availableContexts
                    clip: true
                    visible: !root.loading && root.availableContexts.length > 0
                    delegate: ContextItem {
                        contextName: modelData
                    }
                }
            }
        }
    }

    popoutWidth: 450
    popoutHeight: 0
}
