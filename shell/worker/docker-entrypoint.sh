#!/bin/bash

ulimit -c 1024



echo "web hook test"


exec "$@"
