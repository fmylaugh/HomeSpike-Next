/**
 * @file ConfirmDeletePageOverlay
 * @description Full-screen modal that asks the user to confirm removing a whole
 *   home page. Self-contained scrim + centered card (same pattern as
 *   ConfirmRemoveOverlay). Tap outside the card or Cancel to dismiss; tap
 *   Delete → emits confirmed(pageIndex).
 *
 *   The apps on the page are removed from HomeSpike (hidden), not uninstalled.
 *
 * @status Stable.
 * @issues None
 * @todo None
 */
import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: root

    /** Index of the page the user is being asked about. */
    property int pageIndex: -1

    /** Emitted when the user taps Delete. */
    signal confirmed(int pageIndex)

    /** Px width of the Lomiri launcher panel overlapping us — keeps the card
     *  centered in the visible content area. */
    property real leftReserve: 0

    anchors.fill: parent
    z: 1000
    visible: false
    color: "#aa000000"

    function show(targetPage) {
        pageIndex = targetPage;
        visible = true;
    }

    // Tap outside the card dismisses.
    MouseArea {
        anchors.fill: parent
        onClicked: root.visible = false
    }

    Rectangle {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.leftReserve / 2
        width: Math.min((parent.width - root.leftReserve) * 0.85, units.gu(50))
        height: cardCol.height + units.gu(4)
        radius: units.gu(2)
        color: "#262d4d"

        MouseArea { anchors.fill: parent }

        Column {
            id: cardCol
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: units.gu(2); rightMargin: units.gu(2)
            }
            spacing: units.gu(2)

            Label {
                text: "Remove this page?"
                color: "white"
                font.bold: true
                fontSize: "large"
                width: parent.width
                wrapMode: Text.WordWrap
            }
            Label {
                text: "This page and its apps will be removed from HomeSpike. The apps stay installed; you can re-add them from the swipe-left drawer."
                color: "#cfd6e4"
                width: parent.width
                wrapMode: Text.WordWrap
            }
            Row {
                anchors.right: parent.right
                spacing: units.gu(1)
                Button {
                    text: "Cancel"
                    onClicked: root.visible = false
                }
                Button {
                    text: "Delete"
                    color: "#e94560"
                    onClicked: {
                        root.confirmed(root.pageIndex);
                        root.visible = false;
                    }
                }
            }
        }
    }
}
