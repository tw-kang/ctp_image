#!/bin/bash

sudo /usr/sbin/sshd
ulimit -c 1024

source ~/.bash_profile

exec "$@"
