                    GNU GENERAL PUBLIC LICENSE
                       Version 2, June 1991

 Copyright (C) 1989, 1991 Free Software Foundation, Inc.,
 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

HomeSpike is licensed under the GNU General Public License, version 2
or (at your option) any later version. The full license text is
available at <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>.

The "or later" clause is deliberate. HomeSpike's QML imports — and
the installer's patches modify — components of the Lomiri shell, which
is licensed GPL-3.0-or-later. The "or-later" upgrade path on this
repo keeps the combined work license-compatible at GPL-3.0 when
deployed against Lomiri on a user's device.

`deploy/install.sh` performs in-place edits to
`/usr/share/lomiri/Shell.qml` on the user's own device using
documented sed substitutions, with the original file preserved as
`Shell.qml.orig`. The patches themselves are derived from analysis
of the GPL-3.0+ Lomiri source. They are applied to the user's
existing installed copy of Lomiri — this repository does not
redistribute modified Lomiri binaries.

The QML app at `app/main.qml`, the wrapper at `app/home-spike`, the
`.desktop` file at `app/home-spike.desktop`, and the installer
scripts under `deploy/` are original work, copyright the project
contributors, released under GPL-2.0-or-later.

Upstream component sources referenced or imported at runtime:
  - Lomiri shell:              https://gitlab.com/ubports/development/core/lomiri
  - lomiri-app-launch:         https://gitlab.com/ubports/development/core/lomiri-app-launch
  - gsettings-qt:              https://gitlab.com/ubports/development/core/gsettings-qt
  - Qt 5 / QtQuick / qmlscene: https://www.qt.io/  (LGPL-3.0 with Qt commercial alternative)

External tools used at runtime keep their own licenses
(Android platform-tools `adb`: Apache-2.0).
