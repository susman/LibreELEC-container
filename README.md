# Containerized LibreElec
[LibreELEC](https://github.com/LibreELEC/LibreELEC.tv) provides a great Kodi build for select hardware architectures. It also provides 'Just enough OS for KODI'.

[Raspberry Pi 4](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/specifications/) with 8GB memory is a very capable machine, having it running only Kodi feels like a waste of resources. LibreELEC/Kodi provided containerization tools are useful but cumbersome. The process described here containerizes LibreELEC, allowing it to be deployed on any GNU/Linux host distro as yet another container.

## Preparing the environment
Podman provides an easier way to run rootless containers, running Kodi as root isn't a good idea.
1. set up a new user to run Podman/Kodi
2. add the user to `video`, `render`, `input`, `audio` and `pipewire` (if required) groups
3. follow the https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md to configure /etc/subuid and /etc/subgid
4. make sure the user is allowed to map required groups
```bash
$ cat /etc/subgid
<kodi-user>:<'video' gid>:1
<kodi-user>:<'render' gid>:1
<kodi-user>:<'input' gid>:1
...
```
Example:
```bash
$ cat /etc/subgid
kodi-user:666:1
kodi-user:69:1
kodi-user:420:1
kodi-user:165536:65536
...
```
5. set up Pipewire-pulse/PulseAudio for the user
6. you might also need to make sure udev sets correct permissions on these devices:
```bash
$ cat /etc/udev/rules.d/01-video.rules
KERNEL=="vcsm-cma", GROUP="video", MODE="0660"
SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
```

## Building the image
First stage of the multi-stage build uses latest Ubuntu image to download LibreELEC disk image and extract root filesystem content using [Fatcat](https://github.com/Gregwar/fatcat) (please don't fat shame cats 😽) and squashfs-tools. Second stage creates root fs from the extracted files, removes a few obviously redundant files, disables/removes LibreELEC settings Kodi addon and sets the timezone.

```bash
podman build -t localhost/libreelec:rpi4-12.0.0 --build-arg=dl_url=https://releases.libreelec.tv/LibreELEC-RPi4.aarch64-12.0.0.img.gz .
```

## Running container
1. find out `video`, `render` and `input` image gids
```bash
$ podman run -t --rm --entrypoint=/bin/ash localhost/libreelec:rpi4-12.0.0 -c "egrep '(video|render|input)' /etc/group"
video:x:39:pipewire
input:x:104:
render:x:105:
```
2. start Kodi:
```bash
podman run --rm --replace --init --privileged \ # as privileged as the user running podman
  --name kodi \
  --hostname kodi \
  --group-add keep-groups \ # keep the groups host user is in
  --gidmap="+g39:@666:1" \ # map this container gid to that host gid
  --gidmap="+g105:@69:1" \
  --gidmap="+g104:@420:1" \
  -v $(realpath /etc/localtime):/etc/localtime:ro \
  -v /dev/input:/dev/input:ro \
  -v /run/udev:/run/udev:ro \
  -v <path-to-kodi-storage-dir>:/storage \ # mount LibreELEC /storage on a local dir
  -v $XDG_RUNTIME_DIR/pulse/native:/tmp/pulse-socket \ # mount host PulseAudio socket
  -e KODI_HOME=/usr/share/kodi \ # Kodi setup
  -e KODI_TEMP=/storage/.kodi/temp \
  -e HOME=/storage \
  -e PULSE_SERVER=unix:/tmp/pulse-socket \
  -p 8080:8080 \ # Kodi web UI ports
  -p 9090:9090 \
  libreelec:rpi4-12.0.0
```

## Trade-off
You get the same great LibreELEC Kodi build but with enhanced security, running on the GNU/Linux flavour of your choice. Trying out new LibreELEC features in nightly builds is a quick and non-destructive process with this approach.
Since LibreELEC settings addon is removed during the build process, all hardware configuration is done on the underlying OS level. Kodi 'power' button does nothing, Kodi built-in services can be forwarded but setting up e.g samba or [shairport](https://github.com/mikebrady/shairport-sync) on the host (or in other containers) would be a better option.
