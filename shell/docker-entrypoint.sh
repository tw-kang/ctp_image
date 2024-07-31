#!/bin/bash

# Start SSH service and set core dump limit
start_ssh_and_set_limits() {
  sudo /usr/sbin/sshd
  ulimit -c 1024
}

# Define the run_checkout function
run_checkout() {
  sudo -E -u shell -i <<EOF
  cd ~/
  git clone --depth 1 -b develop https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testcases.git
  git clone --depth 1 -b develop https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testcases-private-ex.git
EOF
}

# Perform common git setup and clone operations
common_setup() {
  local user=$1
  sudo -E -u $user -i <<EOF
  git config --global pack.threads 4
  git clone --depth 1 -b develop https://github.com/CUBRID/cubrid-testtools.git /home/$user/cubrid-testtools
  sudo cp -rf /home/$user/cubrid-testtools/CTP /home/$user/
  sudo chown -R $user:$user /home/$user/CTP
EOF
}

# Configure the controller environment
configure_controller() {
  $(declare -f common_setup)
  common_setup shell_ctrl
  sudo -E -u shell_ctrl -i <<EOF
  cd /home/shell_ctrl
  echo "#JAVA ENV" >> /home/shell_ctrl/.bash_profile
  echo "export JAVA_HOME=/usr/lib/jvm/java-1.8.0" >> /home/shell_ctrl/.bash_profile
  echo "#CTP ENV" >> /home/shell_ctrl/.bash_profile
  echo "export CTP_HOME=/home/shell_ctrl/CTP" >> /home/shell_ctrl/.bash_profile
  echo "export PATH=\$CTP_HOME/bin:\$CTP_HOME/common/script:\$PATH" >> /home/shell_ctrl/.bash_profile
  echo "export CTP_BRANCH_NAME=develop" >> /home/shell_ctrl/.bash_profile
  echo "export CTP_SKIP_UPDATE=0" >> /home/shell_ctrl/.bash_profile
  source ~/.bash_profile
EOF
}

# Configure the worker environment
configure_worker() {
  $(declare -f common_setup)
  $(declare -f run_checkout)
  common_setup shell
  sudo -E -u shell -i <<EOF
  cd /home/shell
  run_checkout
  echo "#JAVA ENV" >> /home/shell/.bash_profile
  echo "export JAVA_HOME=/usr/lib/jvm/java-1.8.0" >> /home/shell/.bash_profile
  echo "#CTP ENV" >> /home/shell/.bash_profile
  echo "export CTP_HOME=/home/shell/CTP" >> /home/shell/.bash_profile
  echo "export PATH=\$CTP_HOME/bin:\$CTP_HOME/common/script:\$PATH" >> /home/shell/.bash_profile
  echo "export CTP_BRANCH_NAME=develop" >> /home/shell/.bash_profile
  echo "export CTP_SKIP_UPDATE=0" >> /home/shell/.bash_profile
  echo "#[shell] ENV" >> /home/shell/.bash_profile
  echo "export init_path=\$CTP_HOME/shell/init_path" >> /home/shell/.bash_profile
  echo "#CUBRID ENV" >> /home/shell/.bash_profile
  echo "export CUBRID=/home/shell/CUBRID" >> /home/shell/.bash_profile
  echo "export CUBRID_DATABASES=\$CUBRID/databases" >> /home/shell/.bash_profile
  echo "export LD_LIBRARY_PATH=\$CUBRID/lib:\$CUBRID/cci/lib:\$LD_LIBRARY_PATH" >> /home/shell/.bash_profile
  echo "export SHLIB_PATH=\$LD_LIBRARY_PATH" >> /home/shell/.bash_profile
  echo "export LIBPATH=\$LD_LIBRARY_PATH" >> /home/shell/.bash_profile
  echo "export PATH=\$CUBRID/bin:/usr/sbin:\$PATH" >> /home/shell/.bash_profile
  source ~/.bash_profile
EOF
}

# Main script execution
main() {
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
