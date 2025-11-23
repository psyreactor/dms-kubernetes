import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "kubernetes"

    StyledText {
        width: parent.width
        text: "Configuración Kubernetes"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configura el path del kubeconfig y el intervalo de actualización."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "kubeconfigPath"
        label: "Kubeconfig Path"
        description: "Path al archivo de configuración de Kubernetes"
        defaultValue: "~/.kube/config"
        placeholder: "~/.kube/config"
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh Interval"
        description: "Intervalo de actualización del contexto (en segundos)."
        defaultValue: 300
        minimum: 30
        maximum: 600
        unit: "seg"
        leftIcon: "schedule"
    }
}
