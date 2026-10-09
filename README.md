# Containerized LibreElec
[LibreELEC](https://github.com/LibreELEC/LibreELEC.tv) provides a great Kodi build for select hardware architectures. It also provides 'Just enough OS for KODI'.

[Raspberry Pi 4](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/specifications/) with 8GB memory is a very capable machine, having it running only Kodi feels like a waste of resources. LibreELEC/Kodi provided containerization tools are useful but cumbersome. The process described here containerizes LibreELEC, allowing it to be deployed on any GNU/Linux host distro as yet another container.

## Preparing the environment
Podman provides easier way to run rootless containers, running Kodi as root isn't a good idea.
1. Set up a new user to run Podman/Kodi
2. Add the user to `video`, `render`, `input`, `audio` and `pipewire` (if required) groups
3. Follow the [Podman rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md) to configure /etc/subuid and /etc/subgid
4. Make sure the user is allowed to map required groups
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
5. Set up Pipewire-pulse/PulseAudio for the user
6. You might also need to make sure udev sets the correct permissions on these devices:
    ```bash
    $ cat /etc/udev/rules.d/01-video.rules
    KERNEL=="vcsm-cma", GROUP="video", MODE="0660"
    SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
    ```

## Building the image
First stage of the multi-stage build uses latest Ubuntu image to download LibreELEC disk image and extract root filesystem content using [Fatcat](https://github.com/Gregwar/fatcat) (please don't fat shame cats 😽) and squashfs-tools. Second stage creates root fs from the extracted files, removes a few obviously redundant files and disables/removes LibreELEC settings Kodi addon.

```bash
podman build -t localhost/kodi:rpi4-12.0.0 --build-arg=dl_url=https://releases.libreelec.tv/LibreELEC-RPi4.aarch64-12.0.0.img.gz .
```

## Running container
1. Find out `video`, `render` and `input` image gids
    ```bash
    $ podman run -t --rm --entrypoint=/bin/ash localhost/kodi:rpi4-12.0.0 -c "egrep '(video|render|input)' /etc/group"
    video:x:39:pipewire
    input:x:104:
    render:x:105:
    ```
2. Start Kodi:
    ```bash
    podman run --rm --replace --init --privileged \ # as privileged as the user running podman
      --name kodi \
      --hostname kodi \
      --group-add keep-groups \ # keep the groups host user is in
      --gidmap="+g39:@666:1" \ # map this container gid to that host gid
      --gidmap="+g105:@69:1" \
      --gidmap="+g104:@420:1" \
      -v /etc/localtime:/etc/localtime:ro \
      -v /dev/input:/dev/input:ro \
      -v /run/udev:/run/udev:ro \
      -v $path_to_kodi_storage_dir:/storage \ # mount LibreELEC /storage on a local dir
      -v $XDG_RUNTIME_DIR/pulse/native:/tmp/pulse-socket \ # mount host PulseAudio socket
      -e KODI_HOME=/usr/share/kodi \ # Kodi setup
      -e KODI_TEMP=/storage/.kodi/temp \
      -e HOME=/storage \
      -e PULSE_SERVER=unix:/tmp/pulse-socket \
      -p 8080:8080 \ # Kodi web UI ports
      -p 9090:9090 \
      kodi:rpi4-12.0.0
    ```

## Podman+systemd
It's much easier to manage the whole thing with systemd units.

### The setup:
```bash
$ mkdir -p ~/containers/kodi/
$ mkdir -p ~/.config/containers/systemd/
$ for x in Containerfile systemd/map-gids.sh; do ln -snf $(realpath $x) ~/containers/kodi/; done
$ for x in systemd/{kodi.build,kodi.container,kodi.volume}; do cp $x ~/.config/containers/systemd/; done
$ for x in systemd/{build-kodi-image.service,map-gids.service}; do cp $x ~/.config/systemd/user/; done
```
Edit the `~/.config/containers/systemd/kodi.build` file to set `BuildArg=dl_url=` variable.
```bash
$ systemctl --user daemon-reload
$ systemctl --user enable --now build-kodi-image.service
$ systemctl --user start kodi.service
```
If you need to migrate your existing kodi storage directory into the `kodi` volume:
```bash
# before 'systemctl --user enable --now build-kodi-image.service'
$ systemctl --user start kodi-volume.service
$ podman run -d --name kodi-volume -v kodi:/tmp/kodi alpine:latest sleep infinity
$ cd $path_to_kodi_storage_dir
$ tar cf - . | podman cp - kodi-volume:/tmp/kodi/
$ podman rm -f -t 0 kodi-volume
```

### How it works:
`build-kodi-image.service` is the only (pure systemd) unit that starts on user login or linger. It only checks if `localhost/kodi:latest` image exists and if it doesn't - starts the `kodi-build.service` podman generated (`kodi.build`) unit. `kodi-build.service` first removes the `~/containers/kodi/unit.env` file which contains gid mappings. This env file is 1) a conditional for `kodi.service` (`kodi.container`) 2) might need to be updated. Once the build process is over, `kodi-build.service` starts the one shot `map-gids.service` which recreates the `~/containers/kodi/unit.env` file, thus allowing `kodi.service` to proceed.

### Try a nightly LibreELEC build:
1. Stop kodi:
    ```bash
    $ systemctl --user stop kodi.service
    ```
2. Find a download link or run `systemd/libreelec-nightly-rpi4.py` (requires beautifulsoup4 Python module).
3. Update the `~/.config/containers/systemd/kodi.build` file (`BuildArg=dl_url=` variable).
4. Regenerate `kodi-build.service` unit:
    ```bash
    $ systemctl --user daemon-reload
    ```
5. Backup kodi storage:
    ```bash
    $ podman volume export kodi > kodi-volume-old.tar.xz
    ```
6. Untag the current latest image:
    ```bash
    $ podman tag localhost/kodi:latest localhost/kodi:old
    $ podman rmi localhost/kodi:latest
    ```
7. Restart `build-kodi-image.service` or reboot.

If things went wrong:

1. Stop `kodi.service` and `kodi-volume.service`
2. Re-tag the old image
    ```bash
    $ podman rmi localhost/kodi:latest
    $ podman tag localhost/kodi:old localhost/kodi:latest
    $ podman rmi localhost/kodi:old
    ```
3. Delete the current volume:
    ```bash
    $ podman volume rm kodi
    ```
4. Start `kodi-volume.service` (create an empty volume)
5. Restore from backup:
    ```bash
    $ podman volume import kodi kodi-volume-old.tar.xz
    ```
6. Start `kodi.service`
7. Relax, today is not the day. Watch a cute cats video 😽.

## Trade-off
You get the same great LibreELEC Kodi build but with enhanced security, running on the GNU/Linux flavour of your choice. Trying out new LibreELEC features in nightly builds is a quick and non-destructive process with this approach.
Since LibreELEC settings addon is removed during the build process, all hardware configuration has to be done on the OS level. Kodi's 'power' button does nothing, Kodi built-in services can be forwarded, but setting up e.g samba or [shairport](https://github.com/mikebrady/shairport-sync) on the host (or as another container) would be a better option.
