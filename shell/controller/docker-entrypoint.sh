#!/bin/bash

sudo /usr/sbin/sshd
ulimit -c 1024

exec "$@"
