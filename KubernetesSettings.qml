import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "kubernetes"

    // Section header: icon, title and a one-line explanation of the group.
    component GroupHeader: RowLayout {
        property string iconName: ""
        property string title: ""
        property string subtitle: ""

        width: parent.width
        spacing: Theme.spacingM

        DankIcon {
            name: iconName
            size: 22
            color: Theme.primary
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                text: title
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                Layout.fillWidth: true
            }

            StyledText {
                text: subtitle
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }

    // Card wrapper matching the popout's cards.
    component SettingsGroup: StyledRect {
        default property alias content: groupCol.data

        width: parent.width
        height: Math.max(0, groupCol.implicitHeight + Theme.spacingM * 2)
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.width: 1
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

        Column {
            id: groupCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingL
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingL

        SettingsGroup {
            GroupHeader {
                iconName: "settings_ethernet"
                title: "Cluster Access"
                subtitle: "Which kubeconfig to read, and how often to re-read it."
            }

            StringSetting {
                settingKey: "kubeconfigPath"
                label: "Kubeconfig Path"
                description: "Path to the Kubernetes configuration file."
                defaultValue: "~/.kube/config"
                placeholder: "~/.kube/config"
            }

            SliderSetting {
                settingKey: "refreshInterval"
                label: "Refresh Interval"
                description: "Frequency of context background updates in seconds."
                defaultValue: 15
                minimum: 10
                maximum: 600
                unit: "sec"
                leftIcon: "schedule"
            }
        }

        SettingsGroup {
            GroupHeader {
                iconName: "visibility"
                title: "Display"
                subtitle: "How the widget renders in the bar and in the popout header."
            }

            ToggleSetting {
                settingKey: "hideContextName"
                label: "Hide cluster name"
                description: "Show only the icon in the bar and reveal the context name on hover."
                defaultValue: false
            }

            SelectionSetting {
                settingKey: "timeFormat"
                label: "Time Format"
                description: "Choose time format for the last-updated indicator."
                options: [
                    {label: "System Default", value: "system"},
                    {label: "12-Hour", value: "12h"},
                    {label: "24-Hour", value: "24h"}
                ]
                defaultValue: "system"
            }
        }
    }
}
