#!/bin/bash

systemctl restart sshd
ulimit -c 1024

exec "$@"
