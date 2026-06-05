/**
 * @file OrientationProbe
 * @description Reports the device's PHYSICAL orientation as an angle (0/90/
 *   180/270), independent of the display rotation — HomeSpike pins the home to
 *   portrait, so the shell's own angle is always 0 and we need the raw sensor.
 *
 *   When the system "Rotation Lock" is enabled (OrientationLock.enabled — the
 *   same source Lomiri's OrientedShell uses), the probe reports portrait (0)
 *   and stops reading the sensor, so HomeSpike's icons / drawer / launcher stay
 *   put — matching the rest of the locked, non-rotating UI. With the lock off it
 *   follows the physical sensor.
 *
 *   Isolated in its own file (loaded via a Loader in main.qml / the shell
 *   overrides) so that if a plugin isn't present on a given device, only this
 *   probe fails to load — HomeSpike still works, just without icon re-orientation.
 *
 * @status Stable.
 * @issues Angle mapping (which physical turn → which angle) may need its signs
 *   adjusted per device; verify on-device and flip LeftUp/RightUp if needed.
 * @todo None
 */
import QtQuick 2.15
import QtSensors 5.0
import Lomiri.Session 0.1

Item {
    id: probe

    /** Current device angle in degrees (0 = upright portrait). */
    property int angle: 0

    /** System Rotation Lock. When on, everything stays portrait. */
    readonly property bool locked: OrientationLock.enabled
    onLockedChanged: if (locked) probe.angle = 0

    OrientationSensor {
        // Don't even read the sensor while locked; angle is pinned to 0 above.
        active: !probe.locked
        onReadingChanged: {
            if (probe.locked || !reading) return;
            switch (reading.orientation) {
            case OrientationReading.TopUp:   probe.angle = 0;   break;
            case OrientationReading.LeftUp:  probe.angle = 270; break;
            case OrientationReading.TopDown: probe.angle = 180; break;
            case OrientationReading.RightUp: probe.angle = 90;  break;
            // FaceUp / FaceDown / Undefined → keep the last angle.
            }
        }
    }
}
