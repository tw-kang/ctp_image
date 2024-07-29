#!/bin/bash

# Start SSH service
sudo /usr/sbin/sshd
ulimit -c 1024

# Source the bash profile to set environment variables
source ~/.bash_profile

# Execute the passed command
exec "$@"