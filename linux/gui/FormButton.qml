import QtQuick
import QtQuick.Controls as Controls

Controls.Button {
    horizontalPadding: 10
    implicitHeight: Math.max(28, contentItem.implicitHeight + 10)
    verticalPadding: 4
}
