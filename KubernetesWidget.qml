import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
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
    property var lastUpdated: null
    // Set by the manual refresh button so the toast only fires for a refresh
    // the user actually asked for, not for every periodic tick.
    property bool manualRefresh: false
    property string toastText: ""

    // Above this many contexts the popout grows a filter field. Below it the
    // list is short enough to scan, and the field would be pure chrome.
    readonly property int searchThreshold: 8

    // Settings
    property string kubeconfigPath: pluginData.kubeconfigPath || "~/.kube/config"
    property int refreshInterval: pluginData.refreshInterval || 300
    property bool hideContextName: pluginData.hideContextName || false
    property string timeFormat: pluginData.timeFormat || "system"
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

    Timer {
        id: toastTimer
        interval: 1800
    }

    function showToast(msg) {
        root.toastText = msg
        toastTimer.restart()
    }

    function getEffectiveTimeFormat() {
        if (root.timeFormat === "12h") return "12h"
        if (root.timeFormat === "24h") return "24h"

        const sysFmt = Qt.locale().timeFormat(Locale.ShortFormat)
        return (sysFmt.indexOf("H") !== -1 || sysFmt.indexOf("k") !== -1) ? "24h" : "12h"
    }

    function formatHeaderTime(dateObj) {
        if (!dateObj) return ""
        return Qt.formatTime(dateObj, getEffectiveTimeFormat() === "24h" ? "HH:mm" : "h:mm AP")
    }

    // If a Proc callback never fires, `loading` would latch true forever and the
    // popout would spin on "Loading contexts..." for the rest of the session.
    // 30s is well above the worst legitimate case: a single `config view` with
    // a 10s Proc timeout.
    Timer {
        id: loadingWatchdog
        interval: 30000
        repeat: false
        running: root.loading
        onTriggered: {
            root.refreshEpoch++
            root.manualRefresh = false
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

    // EKS ARNs carry the useful bits: arn:aws:eks:<region>:<account>:cluster/<name>.
    // Anything else falls back to the raw cluster string.
    function shortCluster(cluster) {
        if (!cluster)
            return ""
        const m = cluster.match(/^arn:aws:eks:([^:]+):[^:]*:cluster\/(.+)$/)
        return m ? (m[1] + " \u00b7 " + m[2]) : cluster
    }

    function parseKubeConfig(stdout) {
        try {
            const data = JSON.parse(stdout)
            return {
                current: data["current-context"] || "",
                contexts: (data.contexts || []).map(c => ({
                    name: c.name,
                    subtitle: root.shortCluster(c.context ? c.context.cluster : "")
                }))
            }
        } catch (e) {
            return null
        }
    }

    function completeRefresh() {
        const wasManual = root.manualRefresh
        root.manualRefresh = false
        root.loading = false
        root.lastUpdated = new Date()

        if (wasManual && !root.hasError)
            root.showToast("Refreshed contexts")
    }

    // One `config view` replaces the old current-context + get-contexts pair: it
    // carries the active context and every context's cluster in a single call,
    // so `loading` now covers the whole fetch instead of clearing halfway.
    function fetchKubeContext() {
        root.loading = true
        const gen = ++root.refreshEpoch
        const expandedPath = root.kubeconfigPath.replace(/^~/, Quickshell.env("HOME"))

        Proc.runCommand(null, ["kubectl", "--kubeconfig", expandedPath, "config", "view", "-o", "json"], (stdout, exitCode) => {
            if (gen !== root.refreshEpoch)
                return

            const parsed = exitCode === 0 ? root.parseKubeConfig(stdout) : null
            if (parsed) {
                root.currentContext = parsed.current || "..."
                root.availableContexts = parsed.contexts
                root.hasError = false
                root.errorMessage = ""
            } else {
                root.hasError = true
                root.errorMessage = "Error: kubectl not found or invalid config"
                root.currentContext = "N/A"
                root.availableContexts = []
            }
            root.completeRefresh()
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

    // A bare Column reports no implicit size in this slot, which renders the
    // vertical pill broken. Same wrapper the sibling notifier plugins use.
    verticalBarPill: Component {
        Item {
            implicitWidth: verticalCol.implicitWidth
            implicitHeight: verticalCol.implicitHeight

            Column {
                id: verticalCol
                anchors.centerIn: parent
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
    }

    // Row for one context. Unlike the notifier plugins these rows are not
    // links: clicking switches the active context, so the trailing affordance
    // is a swap hint rather than open_in_new.
    component ContextItem: Item {
        id: ctxRow

        required property var modelData
        required property int index
        property int total: 0

        readonly property string contextName: modelData ? modelData.name : ""
        readonly property string contextSubtitle: modelData ? (modelData.subtitle || "") : ""
        readonly property bool isCurrent: contextName === root.currentContext
        readonly property bool isHovered: ctxMa.containsMouse
        readonly property bool isFirst: index === 0
        readonly property bool isLast: index === ctxRow.total - 1

        width: parent ? parent.width : 0
        height: Math.max(56, ctxLayout.implicitHeight + Theme.spacingS * 2)

        Shape {
            id: ctxBg
            anchors.fill: parent

            readonly property real innerRadius: 6
            readonly property real outerRadius: Theme.cornerRadius || 12
            readonly property real topR: ctxRow.isHovered ? (height / 2) : (ctxRow.isFirst ? outerRadius : innerRadius)
            readonly property real bottomR: ctxRow.isHovered ? (height / 2) : (ctxRow.isLast ? outerRadius : innerRadius)

            property real topRAnim: topR
            Behavior on topRAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
            property real bottomRAnim: bottomR
            Behavior on bottomRAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

            ShapePath {
                fillColor: ctxRow.isCurrent
                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                           : (ctxRow.isHovered
                              ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                              : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04))
                strokeColor: ctxRow.isCurrent
                             ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                             : (ctxRow.isHovered
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15))
                strokeWidth: 1

                startX: ctxBg.topRAnim + 1; startY: 1
                PathLine { x: ctxBg.width - ctxBg.topRAnim - 1; y: 1 }
                PathArc { x: ctxBg.width - 1; y: ctxBg.topRAnim + 1; radiusX: ctxBg.topRAnim; radiusY: ctxBg.topRAnim; direction: PathArc.Clockwise }
                PathLine { x: ctxBg.width - 1; y: ctxBg.height - ctxBg.bottomRAnim - 1 }
                PathArc { x: ctxBg.width - ctxBg.bottomRAnim - 1; y: ctxBg.height - 1; radiusX: ctxBg.bottomRAnim; radiusY: ctxBg.bottomRAnim; direction: PathArc.Clockwise }
                PathLine { x: ctxBg.bottomRAnim + 1; y: ctxBg.height - 1 }
                PathArc { x: 1; y: ctxBg.height - ctxBg.bottomRAnim - 1; radiusX: ctxBg.bottomRAnim; radiusY: ctxBg.bottomRAnim; direction: PathArc.Clockwise }
                PathLine { x: 1; y: ctxBg.topRAnim + 1 }
                PathArc { x: ctxBg.topRAnim + 1; y: 1; radiusX: ctxBg.topRAnim; radiusY: ctxBg.topRAnim; direction: PathArc.Clockwise }
            }
        }

        DankRipple {
            id: ctxRipple
            anchors.fill: parent
            cornerRadius: ctxBg.topRAnim
            rippleColor: Theme.primary
        }

        RowLayout {
            id: ctxLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingM

            DankIcon {
                name: ctxRow.isCurrent ? "check_circle" : "radio_button_unchecked"
                size: 18
                color: ctxRow.isCurrent ? Theme.primary : Theme.surfaceVariantText
                opacity: ctxRow.isCurrent ? 1.0 : 0.6
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    text: ctxRow.contextName
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: ctxRow.isCurrent ? Font.Bold : Font.Medium
                    color: Theme.surfaceText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                StyledText {
                    text: ctxRow.contextSubtitle
                    font.pixelSize: Theme.fontSizeSmall
                    color: ctxRow.isHovered ? Theme.primary : Theme.surfaceVariantText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    visible: ctxRow.contextSubtitle.length > 0
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            DankIcon {
                name: "swap_horiz"
                size: 16
                color: Theme.primary
                opacity: (ctxRow.isHovered && !ctxRow.isCurrent) ? 0.9 : 0.0
                Layout.alignment: Qt.AlignVCenter
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }

        MouseArea {
            id: ctxMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: ctxRow.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
            onPressed: m => ctxRipple.trigger(m.x, m.y)
            onClicked: {
                if (!ctxRow.isCurrent) {
                    root.switchContext(ctxRow.contextName)
                    root.closePopout()
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popoutRoot
            headerText: ""
            showCloseButton: false

            // The filter lives here rather than on root: this Component is
            // rebuilt on every open, so the query starts empty each time
            // instead of silently carrying over a filter you forgot about.
            property string searchQuery: ""

            readonly property bool showSearch: root.availableContexts.length > root.searchThreshold

            readonly property var filteredContexts: {
                const q = popoutRoot.searchQuery.trim().toLowerCase()
                if (!q)
                    return root.availableContexts
                return root.availableContexts.filter(c => c.name.toLowerCase().includes(q))
            }

            // Injected by PluginPopout; used to hide the bar tooltip while the popout is open.
            property var parentPopout: null
            onParentPopoutChanged: if (parentPopout) root.popoutOpen = parentPopout.shouldBeVisible

            Connections {
                target: popoutRoot.parentPopout
                ignoreUnknownSignals: true
                function onShouldBeVisibleChanged() {
                    root.popoutOpen = popoutRoot.parentPopout.shouldBeVisible
                }
            }

            Component.onDestruction: root.popoutOpen = false

            Item {
                width: parent.width
                height: mainCol.implicitHeight

                Column {
                    id: mainCol
                    width: parent.width
                    spacing: Theme.spacingM
                    topPadding: 0
                    bottomPadding: 2

                    // Header card
                    StyledRect {
                        width: parent.width
                        height: 72
                        radius: Theme.cornerRadius * 1.5
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: headerRefreshBtn.left
                            anchors.rightMargin: Theme.spacingS
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
                                width: parent.width - 32 - Theme.spacingM

                                StyledText {
                                    width: parent.width
                                    text: root.displayContext
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeLarge
                                    color: root.hasError ? Theme.error : Theme.surfaceText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.lastUpdated
                                          ? (root.availableContexts.length + " Contexts • Updated " + root.formatHeaderTime(root.lastUpdated))
                                          : (root.availableContexts.length + " Contexts")
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    color: Theme.primary
                                    opacity: 0.85
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            id: headerRefreshBtn
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            height: 38
                            radius: Theme.cornerRadius
                            color: refreshMa.containsMouse
                                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                   : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, refreshMa.containsMouse ? 0.3 : 0.15)

                            scale: refreshMa.pressed ? 0.92 : (refreshMa.containsMouse ? 1.05 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }

                            DankRipple { id: refreshRipple; anchors.fill: parent; cornerRadius: Theme.cornerRadius; rippleColor: Theme.primary }

                            DankSpinner {
                                size: 20
                                color: Theme.primary
                                anchors.centerIn: parent
                                visible: root.loading
                            }

                            DankIcon {
                                name: "refresh"
                                size: 20
                                color: Theme.primary
                                anchors.centerIn: parent
                                visible: !root.loading

                                rotation: refreshMa.containsMouse ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            }

                            MouseArea {
                                id: refreshMa
                                anchors.fill: parent
                                hoverEnabled: !root.loading
                                cursorShape: Qt.PointingHandCursor
                                onPressed: m => refreshRipple.trigger(m.x, m.y)
                                onClicked: {
                                    root.manualRefresh = true
                                    root.fetchKubeContext()
                                }
                            }
                        }
                    }

                    // Error card
                    StyledRect {
                        width: parent.width
                        visible: root.hasError && root.errorMessage.length > 0
                        height: Math.max(0, errText.implicitHeight + Theme.spacingM * 2)
                        radius: Theme.cornerRadius
                        color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
                        border.width: 1
                        border.color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.4)

                        StyledText {
                            id: errText
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: root.errorMessage
                            color: Theme.error
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    // Contexts card
                    StyledRect {
                        width: parent.width
                        height: Math.max(0, contextsCol.implicitHeight + Theme.spacingM * 2)
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                        Column {
                            id: contextsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            RowLayout {
                                width: parent.width
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: "lan"
                                    size: 14
                                    color: Theme.surfaceText
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                StyledText {
                                    text: "Contexts"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                StyledText {
                                    text: root.availableContexts.length.toString()
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                    opacity: 0.7
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: root.availableContexts.length > 0
                                }
                            }

                            // Context filter. Only worth its chrome once the list stops
                            // fitting on screen, so it stays out of the way for small
                            // kubeconfigs.
                            DankTextField {
                                id: searchField
                                width: parent.width
                                height: 44
                                visible: popoutRoot.showSearch && !root.loading && !root.hasError
                                leftIconName: "search"
                                leftIconSize: Theme.iconSize
                                leftIconColor: Theme.surfaceVariantText
                                leftIconFocusedColor: Theme.primary
                                showClearButton: true
                                textColor: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                placeholderText: "Filter contexts..."
                                focus: visible

                                onVisibleChanged: if (visible) Qt.callLater(() => searchField.forceActiveFocus())
                                Component.onCompleted: if (visible) Qt.callLater(() => searchField.forceActiveFocus())

                                onTextEdited: popoutRoot.searchQuery = text

                                onAccepted: {
                                    const hits = popoutRoot.filteredContexts
                                    if (hits.length > 0 && hits[0].name !== root.currentContext)
                                        root.switchContext(hits[0].name)
                                    root.closePopout()
                                }

                                // Escape clears the filter first; once it is empty the event
                                // is left unaccepted so PluginPopout's handler closes the popout.
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape && text.length > 0) {
                                        text = ""
                                        popoutRoot.searchQuery = ""
                                        event.accepted = true
                                    }
                                }
                            }

                            // Loading state
                            StyledRect {
                                width: parent.width
                                height: 44
                                radius: Theme.cornerRadius
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                                border.width: 1
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                visible: root.loading

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingS

                                    DankSpinner {
                                        size: 18
                                        color: Theme.primary
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: "Loading contexts..."
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }

                            // Empty state. Distinguishes an empty kubeconfig from a filter
                            // that simply matched nothing.
                            StyledRect {
                                width: parent.width
                                height: 44
                                radius: Theme.cornerRadius
                                color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.05)
                                border.width: 1
                                border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.12)
                                visible: !root.loading && popoutRoot.filteredContexts.length === 0

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingS

                                    DankIcon {
                                        name: "info"
                                        size: 18
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: popoutRoot.searchQuery.trim().length > 0
                                              ? "No contexts match"
                                              : "No contexts found"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }

                            // The list itself, scrollable past four contexts
                            Item {
                                width: parent.width
                                height: popoutRoot.filteredContexts.length > 4 ? 244 : ctxColumn.implicitHeight
                                visible: !root.loading && popoutRoot.filteredContexts.length > 0

                                ScrollView {
                                    id: ctxScrollView
                                    anchors.fill: parent
                                    contentWidth: availableWidth

                                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                    ScrollBar.vertical: ScrollBar {
                                        id: ctxScrollBar
                                        policy: popoutRoot.filteredContexts.length > 4 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                                        active: true
                                        width: 6

                                        contentItem: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: ctxScrollBar.pressed
                                                   ? Theme.primary
                                                   : (ctxScrollBar.hovered
                                                      ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.7)
                                                      : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4))
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        background: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.2)
                                        }
                                    }

                                    Column {
                                        id: ctxColumn
                                        width: ctxScrollView.availableWidth
                                        spacing: 4

                                        Repeater {
                                            model: popoutRoot.filteredContexts

                                            delegate: ContextItem {
                                                total: popoutRoot.filteredContexts.length
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Toast, shown only for a refresh the user asked for
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spacingS
                    height: 32
                    width: toastLayout.implicitWidth + Theme.spacingM * 2
                    radius: height / 2
                    color: Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.95)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                    z: 999
                    opacity: toastTimer.running ? 1.0 : 0.0
                    scale: toastTimer.running ? 1.0 : 0.75

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    RowLayout {
                        id: toastLayout
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon { name: "info"; size: 16; color: Theme.primary }

                        StyledText {
                            text: root.toastText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 420
    popoutHeight: 0
}
