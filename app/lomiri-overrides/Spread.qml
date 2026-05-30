/**
 * @file Spread
 * @description HomeSpike's modified copy of Lomiri's app-spread (the
 *   right-swipe task switcher). Adds a "home" button at the bottom-
 *   center that closes the spread and focuses HomeSpike. The bottom
 *   10% of the spread height is already empty padding (contentMargin
 *   on top and bottom of the cards), so the button doesn't displace
 *   any card geometry — it just fills the previously-empty bottom
 *   strip with something useful.
 *
 *   Original file: /usr/share/lomiri/Stage/Spread/Spread.qml
 *   Installed by HomeSpike's install.sh; original preserved as .orig.
 *
 * @status Stable.
 * @issues OTA-fragile — Lomiri upstream updates overwrite our copy.
 *   install.sh re-applies on demand. Same as Drawer.qml.
 * @todo
 *   - [ ] Hide the HomeSpike card itself from the spread (currently it
 *         still appears in the card list). Requires modifying the
 *         appRepeater in Stage.qml — separate, bigger patch.
 */
/*
 * Copyright (C) 2016 Canonical Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.15
import Lomiri.Components 1.3
import "MathUtils.js" as MathUtils

Item {
    id: root

    // HomeSpike: Stage.qml binds this to its own `spreadShown`. When false
    // we MUST keep the home button invisible AND disable its MouseArea,
    // otherwise the always-anchored button swallows touches near the
    // bottom of the screen even when the spread isn't shown — which
    // looks like a frozen phone.
    property bool active: false

    // Information about the environment
    property int highlightedIndex: -1
    property var model: null
    property int leftMargin: 0
    property var spreadFlickable

    // some config options
    property real contentMargin: 0.1 * root.height
    property real contentTopMargin: contentMargin + root.y + windowTitle.height
    property real contentBottomMargin: contentMargin
    property real windowTitleTopMargin: contentMargin - windowTitle.height
    property int stackItemCount: 3
    property real leftRotationAngle: 22
    property real rightRotationAngle: 32
    property real leftStackScale: .82
    property real rightStackScale: 1
    property real rightEdgeBreakPoint: Math.min(units.gu(40) / root.width, .35)

    signal leaveSpread()
    signal closeCurrentApp();
    // HomeSpike: emitted when the user taps the home button in the spread.
    // Stage.qml's `onHomeRequested` handler minimises all apps so the
    // HomeSpike background layer is revealed.
    signal homeRequested()

    // Calculated stuff
    readonly property int totalItemCount: model.count
    readonly property real leftStackXPos: 0.03 * root.width + leftMargin
    readonly property real rightStackXPos: root.width - 1.5 * leftStackXPos + leftMargin

    readonly property real stackHeight: spreadItemHeight - appInfoHeight
    readonly property real stackWidth: Math.min(leftStackXPos/3, units.gu(1.5))

    readonly property real spreadWidth: rightStackXPos - leftStackXPos
    readonly property real spreadHeight: root.height
    readonly property real spreadItemHeight: spreadHeight - contentMargin * 2
    readonly property real spreadItemWidth: stackHeight

    readonly property real dynamicLeftRotationAngle: leftRotationAngle * rotationAngleFactor
    readonly property real dynamicRightRotationAngle: rightRotationAngle * rotationAngleFactor

    readonly property real appInfoHeight: {
        var screenHeightReferencePoint = 40 // ref screen height in gu
        var valueAtReferencePoint = 0.17 // of screen height at the reference point
        var appInfoHeightValueChange = -0.0014 // units / gu
        var minAppInfoHeight = 0.08
        var maxAppInfoHeight = 0.2
        var screenHeightInGU = root.height / units.gu(1) // screenHeight in gu

        return MathUtils.clamp(valueAtReferencePoint + appInfoHeightValueChange * (screenHeightInGU - screenHeightReferencePoint), minAppInfoHeight, maxAppInfoHeight) * root.height
    }

    property real rotationAngleFactor: {
        var spreadHeightReferencePoint = 28 // reference spread height in gu
        var valueAtReferencePoint = 1.3
        var rotationAngleValueChange = -0.008 // units / gu
        var minRotationAngleFactor = 0.6
        var maxRotationAngleFactor = 1.5
        var spreadHeightInGU = spreadHeight / units.gu(1)

        return MathUtils.clamp(valueAtReferencePoint + rotationAngleValueChange * (spreadHeightInGU - spreadHeightReferencePoint), minRotationAngleFactor, maxRotationAngleFactor)
    }
    readonly property real itemOverlap: {
        var spreadAspectRatioReferencePoint = 1.0 // ref screen height in gu
        var valueAtReferencePoint = 0.74 // of screen height at the reference point
        var itemOverlapValueChange = -0.068
        var minOverlap = 0.55
        var maxOverlap = 0.82
        var spreadAspectRatio = spreadWidth / stackHeight // spread stack aspect ratio (app info not included)

        return MathUtils.clamp(valueAtReferencePoint + itemOverlapValueChange * (spreadAspectRatio - spreadAspectRatioReferencePoint), minOverlap, maxOverlap)
    }

    readonly property real visibleItemCount: (spreadWidth / spreadItemWidth) / (1 - itemOverlap)

    readonly property real spreadTotalWidth: Math.max(2,totalItemCount) * spreadWidth / visibleItemCount

    readonly property real centeringOffset: Math.max(spreadWidth - spreadTotalWidth + (leftStackXPos - leftMargin) * 2, 0) / (2 * spreadWidth)

    readonly property var curve: BezierCurve {
        controlPoint2: {'x': 0.19, 'y': 0.00}
        controlPoint3: {'x': 0.91, 'y': 1.00}
    }

    Label {
        id: windowTitle

        width: Math.min(implicitWidth, 0.5*root.width)
        elide: Qt.ElideMiddle
        anchors.horizontalCenter: parent.horizontalCenter
        y: windowTitleTopMargin
        readonly property var highlightedSurface: root.model ? root.model.surfaceAt(root.highlightedIndex) : null
        readonly property var highlightedApp: root.model ? root.model.applicationAt(root.highlightedIndex) : null
        text: root.highlightedIndex >= 0 && highlightedSurface && highlightedSurface.name != "" ? highlightedSurface.name :
                                                                                                  highlightedApp ? highlightedApp.name : ""
        fontSize: root.height < units.gu(85) ? 'medium' : 'large'
        color: "#FFFFFF"
        opacity: root.highlightedIndex >= 0 ? 1 : 0
        Behavior on opacity { LomiriNumberAnimation { } }
    }

    readonly property int itemCount: root.model.count
    onItemCountChanged: {
        if (highlightedIndex >= itemCount) {
            highlightedIndex = itemCount - 1
        }
    }

    Keys.onPressed: {
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_Backtab:
            selectPrevious(event.isAutoRepeat)
            event.accepted = true;
            break;
        case Qt.Key_Right:
        case Qt.Key_Tab:
            selectNext(event.isAutoRepeat)
            event.accepted = true;
            break;
        case Qt.Key_Q:
            closeCurrentApp();
            break;
        case Qt.Key_Escape:
            highlightedIndex = -1
            // Falling through intentionally
        case Qt.Key_Enter:
        case Qt.Key_Return:
        case Qt.Key_Space:
            root.leaveSpread();
            event.accepted = true;
        }
    }


    function selectNext(isAutoRepeat) {
        if (isAutoRepeat && highlightedIndex >= totalItemCount -1) {
            return; // AutoRepeat is not allowed to wrap around
        }

        highlightedIndex = (highlightedIndex + 1) % totalItemCount;
        spreadFlickable.snap(highlightedIndex)
    }

    function selectPrevious(isAutoRepeat) {
        if (isAutoRepeat && highlightedIndex == 0) {
            return; // AutoRepeat is not allowed to wrap around
        }

        highlightedIndex = highlightedIndex - 1 >= 0 ? highlightedIndex - 1 : totalItemCount - 1;
        spreadFlickable.snap(highlightedIndex)
    }

    // ============================================================
    // HomeSpike: home button at the bottom of the spread.
    // Tap closes the spread and focuses HomeSpike via the URL
    // dispatcher (no need to wire anything in Stage.qml).
    // ============================================================
    Rectangle {
        id: homeButton
        objectName: "homeSpikeHomeButton"
        visible: root.active
        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        // Above card layer so it isn't hidden behind app surface thumbnails
        z: 9999
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: units.gu(2)
        width: units.gu(7)
        height: width
        radius: width / 2
        color: homeButtonMouse.pressed ? "#5566c7ff" : "#3344b0ff"
        border.color: "#88ffffff"
        border.width: 1
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
            anchors.centerIn: parent
            text: "⌂"
            color: "white"
            font.pixelSize: parent.height * 0.55
            font.bold: true
        }

        MouseArea {
            id: homeButtonMouse
            anchors.fill: parent
            enabled: root.active   // critical: blocks taps when spread isn't shown
            onClicked: {
                root.homeRequested();
                root.leaveSpread();
            }
        }
    }
}
