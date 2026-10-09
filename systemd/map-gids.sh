#!/usr/bin/env bash
set -xe
cont_groups+=($(podman run -t --rm --entrypoint=/bin/ash localhost/kodi:latest \
  -c "egrep '(video|render|input)' /etc/group"))

for x in ${!cont_groups[@]}; do
  ent=${cont_groups[$x]}
  gr=$(echo $ent | cut -d: -f1)
  cont_guid=$(echo $ent | cut -d: -f3)
  gr_cap=$(echo $gr | tr [:lower:] [:upper:])
  env_rec+=(${gr_cap}=+g${cont_guid}:@$(getent group $gr | cut -d: -f3):1)
done

echo ${env_rec[*]} | tr ' ' '\n' > "$1"
