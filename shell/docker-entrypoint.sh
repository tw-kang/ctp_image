#!/bin/bash

DEBUG=true

# Function to print debug messages
debug() {
  [ "$DEBUG" = true ] && echo "[debug] $1 : $2"
}

# Start SSH service and set core dump limits
start_ssh_and_set_limits() {
  debug "start_ssh_and_set_limits()" "$LINENO"
  sudo /usr/sbin/sshd
  ulimit -c 1024
}

# Function to clone Git repository
clone_repository() {
  local user=$1
  local repo=$2
  local branch=${3:-develop}
  local token=${4:-}
  local workdir=/home/$user
  local url="https://${token:+$token@}github.com/CUBRID/$repo.git"
  
  sudo -u "$user" git clone --depth 1 -q --branch "$branch" "$url" "$workdir/$repo"
}

# Git configuration and repository cloning
setup_git_repositories() {
  local user=$1
  debug "setup_git_repositories user=$user" "$LINENO"
  
  sudo -u "$user" git config --global pack.threads 0
  clone_repository "$user" "cubrid-testtools"
  
  if [ "$user" == "shell" ]; then
    debug "cloning private repositories" "$LINENO"
    clone_repository "$user" "cubrid-testcases" "develop" "${GITHUB_TOKEN}"
    clone_repository "$user" "cubrid-testcases-private-ex" "develop" "${GITHUB_TOKEN}"
  fi
}

# Function to set up environment variables
setup_environment() {
  local user=$1
  local workdir=/home/$user
  local profile=$workdir/.bash_profile
  
  # Set common environment variables
  sudo -u "$user" cat <<'EOF' >> "$profile"
#JAVA ENV
export JAVA_HOME=/usr/lib/jvm/java-1.8.0
#CTP ENV
export CTP_HOME=$workdir/cubrid-testtools/CTP
export PATH=$CTP_HOME/bin:$CTP_HOME/common/script:$PATH
export CTP_BRANCH_NAME=develop
export CTP_SKIP_UPDATE=0
EOF

  # Set shell user specific environment variables
  if [ "$user" == "shell" ]; then
    sudo -u "$user" cat <<'EOF' >> "$profile"
#[shell] ENV
export init_path=$CTP_HOME/shell/init_path
#CUBRID ENV
export CUBRID=$workdir/CUBRID
export CUBRID_DATABASES=$CUBRID/databases
export LD_LIBRARY_PATH=$CUBRID/lib:$CUBRID/cci/lib:$LD_LIBRARY_PATH
export SHLIB_PATH=$LD_LIBRARY_PATH
export LIBPATH=$LD_LIBRARY_PATH
export PATH=$CUBRID/bin:/usr/sbin:$PATH
EOF
  fi
}

# Function to configure environment
configure() {
  local user=$1
  debug "configure user=$user" "$LINENO"
  setup_git_repositories "$user"
  setup_environment "$user"
}

# Main execution function
main() {
  debug "main" "$LINENO"
  start_ssh_and_set_limits

  local role=$1
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

  debug "Container [$role] IP: $(hostname -I)" "$LINENO"

  shift
  if [ "$#" -gt 0 ]; then
    debug "Executing passed command: $@" "$LINENO"
    exec "$@"
  else
    debug "No command passed. Keeping container alive with tail -f /dev/null" "$LINENO"
    exec tail -f /dev/null
  fi
}

main "$@"
