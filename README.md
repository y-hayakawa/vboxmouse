# VBoxMouse
VirtualBox guest addition mouse driver for NEXTSTEP 3.3 (Intel)

There are very few NEXTSTEP-specific drivers developed for VirtualBox, and no Guest Additions are available.

For the display adapter, Vittorio Carosa’s VBoxVideo is publicly available(https://github.com/vcarosadev/VBoxVideo), and it’s been extremely useful.

On the other hand, when using VirtualBox’s PS/2 mouse emulation with NextSTEP, pointer movements feel clumsy, and combining it with the host key is also awkward. That’s why I decided to create a dedicated mouse driver.

It’s still only at a “just about working” stage, but I’ve chosen to release it for NextSTEP enthusiasts. The code may be rough and incomplete, but I hope that anyone with expertise will help improve it further.
