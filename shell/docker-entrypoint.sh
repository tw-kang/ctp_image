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

# Define the run_checkout function
run_checkout() {
  debug "run_checkout" "$LINENO"
  sudo -u shell -i bash -c "
    export GITHUB_TOKEN=${GITHUB_TOKEN}
    echo debug - $GITHUB_TOKEN
    cd /home/shell
    git clone --depth 1 -b develop https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testcases.git
    git clone --depth 1 -b develop https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testcases-private-ex.git
  "
}

# Perform common git setup and clone operations
common_setup() {
  local user=$1
  debug "common_setup , user : $user" "$LINENO"
  sudo -u $user -i bash -c "
    git config --global pack.threads 0
    git clone --depth 1 -b develop https://github.com/CUBRID/cubrid-testtools.git /home/$user/cubrid-testtools &&
    sudo cp -rf /home/$user/cubrid-testtools/CTP /home/$user/ &&
    sudo chown -R $user:$user /home/$user/CTP
  "
}

# Configure the controller environment
configure_controller() {
  debug "configure_controller" "$LINENO"
  $(declare -f common_setup)
  common_setup 'shell_ctrl'
  sudo -u shell_ctrl -i bash -c "
    cd /home/shell_ctrl
    echo '#JAVA ENV' >> /home/shell_ctrl/.bash_profile
    echo 'export JAVA_HOME=/usr/lib/jvm/java-1.8.0' >> /home/shell_ctrl/.bash_profile
    echo '#CTP ENV' >> /home/shell_ctrl/.bash_profile
    echo 'export CTP_HOME=/home/shell_ctrl/CTP' >> /home/shell_ctrl/.bash_profile
    echo 'export PATH=\$CTP_HOME/bin:\$CTP_HOME/common/script:\$PATH' >> /home/shell_ctrl/.bash_profile
    echo 'export CTP_BRANCH_NAME=develop' >> /home/shell_ctrl/.bash_profile
    echo 'export CTP_SKIP_UPDATE=0' >> /home/shell_ctrl/.bash_profile
    source ~/.bash_profile
  "
}

# Configure the worker environment
configure_worker() {
  debug "configure_worker" "$LINENO"
  $(declare -f common_setup)
  $(declare -f run_checkout)
  common_setup 'shell'
  sudo -u shell -i bash -c "
    cd /home/shell
    run_checkout
    echo '#JAVA ENV' >> /home/shell/.bash_profile
    echo 'export JAVA_HOME=/usr/lib/jvm/java-1.8.0' >> /home/shell/.bash_profile
    echo '#CTP ENV' >> /home/shell/.bash_profile
    echo 'export CTP_HOME=/home/shell/CTP' >> /home/shell/.bash_profile
    echo 'export PATH=\$CTP_HOME/bin:\$CTP_HOME/common/script:\$PATH' >> /home/shell/.bash_profile
    echo 'export CTP_BRANCH_NAME=develop' >> /home/shell/.bash_profile
    echo 'export CTP_SKIP_UPDATE=0' >> /home/shell/.bash_profile
    echo '#[shell] ENV' >> /home/shell/.bash_profile
    echo 'export init_path=\$CTP_HOME/shell/init_path' >> /home/shell/.bash_profile
    echo '#CUBRID ENV' >> /home/shell/.bash_profile
    echo 'export CUBRID=/home/shell/CUBRID' >> /home/shell/.bash_profile
    echo 'export CUBRID_DATABASES=\$CUBRID/databases' >> /home/shell/.bash_profile
    echo 'export LD_LIBRARY_PATH=\$CUBRID/lib:\$CUBRID/cci/lib:\$LD_LIBRARY_PATH' >> /home/shell/.bash_profile
    echo 'export SHLIB_PATH=\$LD_LIBRARY_PATH' >> /home/shell/.bash_profile
    echo 'export LIBPATH=\$LD_LIBRARY_PATH' >> /home/shell/.bash_profile
    echo 'export PATH=\$CUBRID/bin:/usr/sbin:\$PATH' >> /home/shell/.bash_profile
    source ~/.bash_profile
  "
}

# Main script execution
main() {
  debug "main" "$LINENO"
  start_ssh_and_set_limits

  role=$1
  case "$role" in
    controller)
      configure_controller
      ;;
    worker)
      configure_worker
      ;;
    *)
      echo "Unknown role: $role. Use 'controller' or 'worker'."
      exit 1
      ;;
  esac

  # Execute the passed command
  shift
  exec "$@"
}

main "$@"
