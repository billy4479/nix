---
name: exec-in-container
description: Use when you want to interact with containers on serverone.
---

Containers on serverone are started by nerdctl as root.

If you just need to see logs you can use `journalctl`, container units are named `nerdctl-<container-name>.service`.

If you need to exec into a container you can use `sudo exec-in-container <container-name> some command`.
When you do so, commands will run as the user inside the container (uid 5000+container_id).
These are live containers with important data on them, be very careful.

