import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    // Same corner radius and colours as the rest of DMS (Settings > Theme).
    SwitcherCore {
        cornerRadius: Theme.cornerRadius
        cardColor: Theme.surfaceContainer
        cardSelected: Theme.primaryContainer
        accent: Theme.primary
        textColor: Theme.surfaceText
        dimColor: Theme.surfaceVariantText
        scrim: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
    }
}
