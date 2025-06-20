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

### TODO
I don’t yet know how the driver can detect when the guest OS’s screen size changes. I tried using the VirtualBox MMIO–based protocol, but it didn’t work correctly.
At present, on every mouse event the driver falls back to using the Bochs VBE Extensions to read the screen size via I/O ports—which is extremely inefficient.
