#!/bin/bash

DEBUG=true
 
debug() {
  if [ "$DEBUG" = true ]; then
    echo "[debug] $1 : $2"
  fi
}

# Start SSH service and set core dump limit
start_ssh_and_set_limits() {
  debug "start_ssh_and_set_limits()" "$LINENO"
  sudo /usr/sbin/sshd
  ulimit -c 1024
}

# Perform common git setup and clone operations
common_setup() {
  local user=$1
  local workdir=/home/$user
  debug "common_setup user=$user" "$LINENO"
  sudo -u "$user" bash -c "
    git config --global pack.threads 0
    git clone --depth 1 -q --branch develop https://github.com/CUBRID/cubrid-testtools.git $workdir/cubrid-testtools
  "

  if [ "$user" == "shell" ]; then
    debug "run_checkout" "$LINENO"
    sudo -u $user bash -c "
      export GITHUB_TOKEN=${GITHUB_TOKEN}
      git clone --depth 1 -q --branch develop https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testcases.git $workdir/cubrid-testcases
      git clone --depth 1 -q --branch develop https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testcases-private-ex.git $workdir/cubrid-testcases-private-ex
    "
  fi
}

# Configure the environment
configure() {
  local user=$1
  local workdir=/home/$user
  debug "configure user=$user" "$LINENO"
  common_setup "$user"
  sudo -u "$user" bash -c "
    cat <<'EOF' >> $workdir/.bash_profile
#JAVA ENV
export JAVA_HOME=/usr/lib/jvm/java-1.8.0
#CTP ENV
export CTP_HOME=$workdir/cubrid-testtools/CTP
export PATH=\$CTP_HOME/bin:\$CTP_HOME/common/script:\$PATH
export CTP_BRANCH_NAME=develop
export CTP_SKIP_UPDATE=0
EOF
  "

  if [ "$user" == "shell" ]; then
    sudo -u "$user" bash -c "
      cat <<'EOF' >> $workdir/.bash_profile
#[shell] ENV
export init_path=\$CTP_HOME/shell/init_path
#CUBRID ENV
export CUBRID=$workdir/CUBRID
export CUBRID_DATABASES=\$CUBRID/databases
export LD_LIBRARY_PATH=\$CUBRID/lib:\$CUBRID/cci/lib:\$LD_LIBRARY_PATH
export SHLIB_PATH=\$LD_LIBRARY_PATH
export LIBPATH=\$LD_LIBRARY_PATH
export PATH=\$CUBRID/bin:/usr/sbin:\$PATH
EOF
    "
  fi
}

# Main script execution
main() {
  debug "main" "$LINENO"
  start_ssh_and_set_limits

  role=$1
  case "$role" in
    controller)
      configure "shell_ctrl"
      ;;
    worker)
      configure "shell"
      ;;
    *)
      echo "Unknown role: $role. Use 'controller' or 'worker'."
      exit 1
      ;;
  esac

  # Display the container's IP address
  debug "Container [$role] IP: $(hostname -I)" "$LINENO"

  # Execute the passed command if there is any
  shift
  if [ "$#" -gt 0 ]; then
    debug "Executing passed command: $@" "$LINENO"
    exec "$@"
  else
    # If no command is passed, keep the container alive
    debug "No command passed. Keeping the container alive with tail -f /dev/null" "$LINENO"
    exec tail -f /dev/null
  fi
}

main "$@"
