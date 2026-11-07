import QtQuick
import QtQuick.Controls as Controls

Controls.ComboBox {
    id: combo

    implicitHeight: Math.max(28, contentItem.implicitHeight + 10)
    verticalPadding: 4

    contentItem: Text {
        color: combo.palette.text
        elide: Text.ElideRight
        font: combo.font
        rightPadding: 20
        text: combo.displayText
        verticalAlignment: Text.AlignVCenter
    }
    indicator: Canvas {
        property color ink: combo.palette.text

        implicitHeight: 18
        implicitWidth: 12
        x: combo.width - width - combo.rightPadding
        y: (combo.height - height) / 2

        onInkChanged: requestPaint()
        onPaint: {
            let c = getContext("2d");
            c.reset();
            c.strokeStyle = ink;
            c.lineWidth = 1.2;
            c.beginPath();
            c.moveTo(2, 6);
            c.lineTo(6, 2);
            c.lineTo(10, 6);
            c.moveTo(2, 12);
            c.lineTo(6, 16);
            c.lineTo(10, 12);
            c.stroke();
        }
    }
}
