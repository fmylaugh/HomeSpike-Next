/**
 * @file PhotoWidget
 * @description Shows a user-chosen photo, framed by a customisable border
 *   (size, corner radius, colour). The image is cropped to fill the widget and
 *   masked to the rounded corners (OpacityMask), with the border drawn on top so
 *   it frames the photo. Until a picture is chosen it shows a "Choose a photo"
 *   hint. The picture/border-size/corner settings come from the per-widget
 *   settings (set in the ⚙ sheet); the border colour is a colour slot.
 *
 *   Same rendering for every size variant — only the grid footprint differs.
 *
 * @status New.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import QtGraphicalEffects 1.0
import Lomiri.Components 1.3

WidgetBase {
    id: root

    readonly property string _src: (settings && settings.image) ? settings.image : ""
    readonly property real _bw: units.gu(_num("borderWidth", 0.5))
    readonly property real _br: units.gu(_num("borderRadius", 1.5))

    function _num(key, def) {
        return (settings && typeof settings[key] === "number") ? settings[key] : def;
    }

    // Rounded, cropped photo — inset by the border so the frame sits around it.
    Item {
        id: holder
        anchors.fill: parent
        anchors.margins: root._bw
        visible: root._src !== ""

        Image {
            id: photo
            anchors.fill: parent
            source: root._src
            fillMode: Image.PreserveAspectCrop
            visible: false
            asynchronous: true
            cache: true
        }
        Rectangle {
            id: photoMask
            anchors.fill: parent
            radius: Math.max(0, root._br - root._bw)
            visible: false
        }
        OpacityMask {
            anchors.fill: parent
            source: photo
            maskSource: photoMask
        }
    }

    // Border frame, drawn over the photo's edge.
    Rectangle {
        anchors.fill: parent
        radius: root._br
        color: "transparent"
        visible: root._bw > 0
        border.width: root._bw
        border.color: root.colorOf("border", "#ffffff")
    }

    // Placeholder until a picture is chosen.
    Label {
        anchors.centerIn: parent
        visible: root._src === ""
        text: "Choose a photo"
        color: "#9fa9c0"
        font.pixelSize: units.gu(1.6)
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: units.gu(1)
        width: parent.width - units.gu(2)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
}
