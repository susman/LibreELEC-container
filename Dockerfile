from ubuntu:latest
arg dl_url

run export DEBIAN_FRONTEND=noninteractive && \
  apt update && apt install -y wget fdisk jq fatcat squashfs-tools-ng && \
  ln -snf /bin/bash /bin/sh && wget $dl_url

run file_name="${dl_url##*/}"; no_ext="${file_name/.img.gz/}"; \
  version="${no_ext##*-}"; gunzip "${file_name}" && \
  part_info="$(sfdisk "${no_ext}.img" -J)" && \
  part_sectorsize="$(echo $part_info | jq '.partitiontable.sectorsize')"; \
  part_start="$(echo $part_info | jq '.partitiontable.partitions[0].start')"; \
  fatcat -O $(($part_start*$part_sectorsize)) "${no_ext}.img" \
    -r /SYSTEM > "${no_ext}.squashfs" && \
  sqfs2tar "${no_ext}.squashfs" > "${no_ext}.tar" && mkdir /root/lelec && \
  tar xpf "${no_ext}.tar" -C /root/lelec

from scratch
copy --from=0 /root/lelec/ /
run mv /usr/lib/systemd/libsystemd-shared-*.so /tmp && \
    rm /etc/hostname && \
    rm -f /usr/bin/systemd* && \
    rm -rf /usr/lib/systemd/* && \
    rm -rf /usr/lib/kernel* && \
    rm -rf /usr/share/alsa && \
    rm -rf /usr/share/kernel* && \
    rm -rf /usr/share/bootloader* && \
    rm -rf /usr/share/kodi/addons/service.libreelec.settings && \
    sed -i 's/.*service\.libreelec\.settings.*//' \
      /usr/share/kodi/system/addon-manifest.xml && \
    ln -s /etc/ssl/cacert.pem.system /run/libreelec/cacert.pem && \
    mv /tmp/libsystemd-shared-*.so /usr/lib/systemd/
entrypoint ["/usr/lib/kodi/kodi.bin", "--standalone", "-fs", "--audio-backend=pulseaudio"]