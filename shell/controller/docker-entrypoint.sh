#!/bin/bash

ulimit -c 1024

exec "$@"
