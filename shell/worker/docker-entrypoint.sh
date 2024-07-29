#!/bin/bash

# Start SSH service
sudo /usr/sbin/sshd
ulimit -c 1024

# Source the bash profile to set environment variables
source ~/.bash_profile

# Define the run_checkout function
run_checkout() {
    git clone --depth 1 -b develop https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testcases.git && \
    git clone --depth 1 -b develop https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testcases-private-ex.git
}

# Call the run_checkout function by default
run_checkout

# Execute the passed command
exec "$@"