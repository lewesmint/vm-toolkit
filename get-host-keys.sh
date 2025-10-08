#!/bin/bash
set -e

rm -f bozo-ssh-host-keys.tar.gz
ssh mintz@bozo "cd /etc/ssh && sudo tar -czf - ssh_host_*" > bozo-ssh-host-keys.tar.gz

mkdir -p /tmp/bozo-keys
tar -xzf bozo-ssh-host-keys.tar.gz -C /tmp/bozo-keys

echo "MD5 hashes of extracted keys:"
cd /tmp/bozo-keys
md5sum ssh_host_*
cd -
