import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "kubernetes"

    StyledText {
        width: parent.width
        text: "Kubernetes config"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure the kubeconfig path and refresh interval."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "kubeconfigPath"
        label: "Kubeconfig Path"
        description: "Path to the Kubernetes configuration file"
        defaultValue: "~/.kube/config"
        placeholder: "~/.kube/config"
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh Interval"
        description: "Context refresh interval (in seconds)."
        defaultValue: 15
        minimum: 10
        maximum: 600
        unit: "sec"
        leftIcon: "schedule"
    }

    ToggleSetting {
        settingKey: "hideContextName"
        label: "Hide cluster name"
        description: "Show only the icon in the bar and reveal the context name on hover."
        defaultValue: false
    }
}
