# VBoxMouse
VirtualBox guest addition mouse driver for NEXTSTEP 3.3 (Intel)

There are very few NEXTSTEP-specific drivers developed for VirtualBox, and no Guest Additions are available.

For the display adapter, Vittorio Carosa’s VBoxVideo is publicly available(https://github.com/vcarosadev/VBoxVideo), and it’s been extremely useful.

On the other hand, when using VirtualBox’s PS/2 mouse emulation with NextSTEP, pointer movements feel clumsy, and combining it with the host key is also awkward. That’s why I decided to create a dedicated mouse driver.

It’s still only at a “just about working” stage, but I’ve chosen to release it for NEXTSTEP enthusiasts. The code may be rough and incomplete, but I hope that anyone with expertise will help improve it further.


### Installation 

- Double-click VBoxMouse.config to copy the driver files into their proper locations.

- Launch Configure.app (in /NextAdmin), go to Mouse settings, and add “VirtualBox Mouse Driver” to enable it.

- Reboot your system—upon restart, the new driver will be active.

Note:\
NEXTSTEP’s Mouse Speed preference will have no effect. All pointer speed and acceleration are governed by the host OS, not by NEXTSTEP.

### Clipboard Sharing (since v0.92)

Starting from version 0.92, support for clipboard (pasteboard) sharing has been added. To use this feature, you need:

- The VBoxMouse driver, and
- A background program called pasteboard_daemon (PBDaemon)

Additionally, you must create a character device file to enable communication between the daemon and the driver.
Run the following commands in the terminal:
```
$ su
# cd /private/dev
# mknod vboxpb c 21 0  
# chmod 666 vboxpb
```
If you are updating from an older version of the VBoxMouse driver, you also need to manually edit the configuration file:

> /private/Devices/VBoxMouse.config/Instance0.table

Add the following line (using a text editor):

> "Character Major" = "21" ;

This allows data exchange via the character device /dev/vboxpb using major number 21.

#### PBDaemon 

To enable clipboard sharing, you must first start the PBDaemon (pasteboard_daemon).
You can build the program by downloading the contents of the PBDaemon folder in this repository and running make. This will generate an executable called pasteboard_daemon.
To start the daemon, run the following command in the terminal:

> pasteboard_daemon

To run it in the background, use the -d option:

> pasteboard_daemon -d

#### VirtualBox Settings

Make sure to enable bidirectional clipboard sharing in the VirtualBox menu:

Devices → Shared Clipboard → Bidirectional

#### ⚠️Notes

- Only plain text (UNICODE) data is supported.
- The maximum size of transferable text is approximately 32,000 characters.

### References and Acknowledgments

- This software is a simple adaptation of VMMouse (the VMware mouse driver) by Jens Heise, updated for recent versions of VirtualBox.  
- [VirtualBox Video Driver](https://github.com/vcarosadev/VBoxVideo) by Vittorio Carosa  
- [VirtualBox Guest Additions](https://wiki.osdev.org/VirtualBox_Guest_Additions)  
- Various resources archived at <https://nextcomputers.org>
