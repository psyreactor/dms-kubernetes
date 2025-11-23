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
    property bool hasError: false
    property string errorMessage: ""
    
    // Settings
    property string kubeconfigPath: pluginData.kubeconfigPath || "~/.kube/config"
    property int refreshInterval: pluginData.refreshInterval || 300

    Timer {
        interval: root.refreshInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchKubeContext()
    }

    function fetchKubeContext() {
        root.loading = true
        const expandedPath = root.kubeconfigPath.replace(/^~/, Quickshell.env("HOME"))
        
        Proc.runCommand("kubernetes.currentContext", ["kubectl", "--kubeconfig", expandedPath, "config", "current-context"], (stdout, exitCode) => {
            if (exitCode === 0) {
                root.currentContext = stdout.trim()
                root.hasError = false
                fetchAllContexts()
            } else {
                root.hasError = true
                root.errorMessage = "Error: kubectl not found or invalid config"
                root.currentContext = "N/A"
            }
            root.loading = false
        }, 100)
    }

    function fetchAllContexts() {
        const expandedPath = root.kubeconfigPath.replace(/^~/, Quickshell.env("HOME"))
        
        Proc.runCommand("kubernetes.allContexts", ["kubectl", "--kubeconfig", expandedPath, "config", "get-contexts", "-o", "name"], (stdout, exitCode) => {
            if (exitCode === 0) {
                root.availableContexts = stdout.trim().split("\n").filter(ctx => ctx.length > 0)
            } else {
                root.availableContexts = []
            }
        }, 100)
    }

    function switchContext(contextName) {
        const expandedPath = root.kubeconfigPath.replace(/^~/, Quickshell.env("HOME"))
        
        Proc.runCommand("kubernetes.switchContext", ["kubectl", "--kubeconfig", expandedPath, "config", "use-context", contextName], (stdout, exitCode) => {
            if (exitCode === 0) {
                fetchKubeContext()
            }
        }, 100)
    }



    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            
            DankIcon {
                name: root.hasError ? "error" : "anchor"
                size: Theme.iconSize - 4
                color: root.hasError ? Theme.error : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
            
            StyledText {
                text: root.loading ? "..." : (root.hasError ? "Error" : root.currentContext)
                color: root.hasError ? Theme.error : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2
            
            DankIcon {
                name: root.hasError ? "error" : "anchor"
                size: 24
                color: root.hasError ? Theme.error : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            StyledText {
                text: root.loading ? "..." : (root.hasError ? "Err" : root.currentContext)
                color: root.hasError ? Theme.error : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    component InfoRow: Row {
        property string label
        property string value
        
        spacing: Theme.spacingM
        width: parent.width
        
        StyledText {
            text: label
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceVariantText
            width: 100
        }
        
        StyledText {
            text: value
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            font.family: "monospace"
        }
    }

    popoutContent: Component {
        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM
            
            // Header
            Row {
                width: parent.width
                spacing: Theme.spacingM
                
                DankIcon {
                    name: "anchor"
                    size: 32
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    
                    StyledText {
                        text: "Kubernetes Contexts"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeLarge
                    }
                    
                    StyledText {
                        text: root.loading ? "Loading..." : "Current: " + root.currentContext
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }
            
            // Error message
            StyledRect {
                width: parent.width
                height: 60
                radius: Theme.cornerRadius
                color: Theme.errorContainer
                visible: root.hasError
                
                StyledText {
                    anchors.centerIn: parent
                    text: root.errorMessage
                    color: Theme.onErrorContainer
                    font.pixelSize: Theme.fontSizeMedium
                }
            }
            
            // Contexts list header
            StyledText {
                text: "Available Contexts (" + root.availableContexts.length + ")"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                visible: !root.hasError && !root.loading && root.availableContexts.length > 0
            }
            
            // Scrollable contexts list
            Item {
                width: parent.width
                height: Math.max(200, parent.height - y)
                visible: !root.hasError && !root.loading && root.availableContexts.length > 0
                
                StyledRect {
                    anchors.fill: parent
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainer
                    
                    ListView {
                        id: contextListView
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        clip: true
                        model: root.availableContexts
                        spacing: Theme.spacingXS
                        
                        delegate: StyledRect {
                            width: ListView.view.width
                            height: 40
                            radius: Theme.cornerRadius
                            color: modelData === root.currentContext ? Theme.primaryContainer : Theme.surfaceContainerHigh
                            border.width: modelData === root.currentContext ? 2 : 0
                            border.color: Theme.primary
                            
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                
                                onClicked: {
                                    if (modelData !== root.currentContext) {
                                        root.switchContext(modelData)
                                        root.closePopout()
                                    }
                                }
                            }
                            
                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS
                                
                                DankIcon {
                                    name: modelData === root.currentContext ? "check_circle" : "radio_button_unchecked"
                                    size: 20
                                    color: modelData === root.currentContext ? "#000000" : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                
                                StyledText {
                                    text: modelData
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: modelData === root.currentContext ? Font.Bold : Font.Normal
                                    color: modelData === root.currentContext ? "#000000" : Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }
            
            // Loading indicator
            Item {
                width: parent.width
                height: 60
                visible: root.loading
                
                Rectangle {
                    id: spinner
                    width: 24
                    height: 24
                    radius: 12
                    color: "transparent"
                    border.width: 3
                    border.color: Theme.surfaceVariantText
                    anchors.centerIn: parent
                    
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: Theme.surfaceVariantText
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    RotationAnimation {
                        target: spinner
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        running: root.loading
                    }
                }
            }
        }
    }

    popoutWidth: 450
    popoutHeight: 500
}
