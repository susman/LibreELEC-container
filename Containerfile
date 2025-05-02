FROM ubuntu:latest
ARG dl_url

RUN export DEBIAN_FRONTEND=noninteractive && \
  apt update && apt install -y wget fdisk jq fatcat squashfs-tools-ng && \
  ln -snf /bin/bash /bin/sh && wget $dl_url

RUN file_name="${dl_url##*/}"; no_ext="${file_name/.img.gz/}"; \
  gunzip "${file_name}" && part_info="$(sfdisk "${no_ext}.img" -J)" && \
  part_sectorsize="$(echo $part_info | jq '.partitiontable.sectorsize')"; \
  part_start="$(echo $part_info | jq '.partitiontable.partitions[0].start')"; \
  mkdir /root/lelec && fatcat -O $(($part_start*$part_sectorsize)) "${no_ext}.img" \
    -r /SYSTEM > "${no_ext}.squashfs" && sqfs2tar "${no_ext}.squashfs" | \
    tar xpf - -C /root/lelec

FROM scratch
COPY --from=0 /root/lelec/ /
RUN mv /usr/lib/systemd/libsystemd-shared-*.so /tmp && \
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
    ln -snf /usr/share/zoneinfo/$(curl -s https://ipapi.co/timezone) \
      /etc/localtime && \
    mv /tmp/libsystemd-shared-*.so /usr/lib/systemd/

ENTRYPOINT ["/usr/lib/kodi/kodi.bin", "--standalone", "-fs", "--audio-backend=pulseaudio"]
