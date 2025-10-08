#!/bin/bash

ssh mintz@bozo 'sudo tar -C /etc/ssh -czf - ssh_host_*' > bozo-ssh-host-keys.tar.gz
