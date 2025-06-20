## Floppy disk image of VBoxMouse

1. Download "VBOXMOUSE-DRIVER.img" in your PC, and mount it from a NEXTSTEP guest OS after started up.
If the floppy disk doesn't appear in File Viewer, choose Workspcae -> Disk -> Check for Disks in the Workspace menu.

2. Double-click VBoxMouse.config to copy the driver files into their proper locations.

3. Launch Configure.app (in /NextAdmin), go to Mouse settings, and add “VirtualBox Mouse Driver” to enable it.

4. Reboot your system—upon restart, the new driver will be active.

Note:\
NEXTSTEP’s Mouse Speed preference will have no effect. All pointer speed and acceleration are governed by the host OS, not by NEXTSTEP.


