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

# Function to clone Git repository with sparse checkout
clone_repository() {
  local user=$1
  local repo=$2
  local branch=${3:-develop}
  local token=${4:-}
  local sparse_dir=${5:-}
  #local url="https://${token:+$token@}github.com/CUBRID/$repo.git"
  local url="https://${token:+$token@}github.com/tw-kang/$repo.git"
  local workdir=/home/$user
  
  if [ -d "$workdir/$repo" ]; then
    sudo -u "$user" bash -c "cd $workdir/$repo && git fetch origin && git checkout $branch && git pull origin $branch"
  else
    if [ -n "$sparse_dir" ]; then
      # Sparse checkout
      sudo -u "$user" bash -c "
        mkdir -p $workdir/$repo &&
        cd $workdir/$repo &&
        git init &&
        git remote add origin $url &&
        git config core.sparseCheckout true &&
        echo '$sparse_dir/*' > .git/info/sparse-checkout &&
        git fetch --depth 1 origin $branch &&
        git checkout $branch
      "
    else
      # full clone
      sudo -u "$user" git clone --depth 1 -q --branch "$branch" "$url" "$workdir/$repo"
    fi
  fi
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
    clone_repository "$user" "cubrid-testcases-private-ex" "develop" "${GITHUB_TOKEN}" "shell"
    # test code
    debug "remove testcase directories" "$LINENO"
    sudo -u "$user" bash -c "
      cd /home/$user/cubrid-testcases-private-ex/shell && \
      find . -maxdepth 1 -type d ! -name '.' ! -name '_01_utility' ! -name 'config' -exec rm -rf {} \;
    "
  fi
}

# Function to set up environment variables
setup_environment() {
  local user=$1
  local workdir=/home/$user
  local ctp_home=$workdir/cubrid-testtools/CTP
  local cubrid_home=$workdir/CUBRID

  debug "configure user=$user" "$LINENO"
  sudo -u "$user" bash -c "
    cat <<EOF >> $workdir/.bash_profile
#JAVA ENV
export JAVA_HOME=/usr/lib/jvm/java-1.8.0
#CTP ENV
export CTP_HOME=$ctp_home
export PATH=$ctp_home/bin:$ctp_home/common/script:$PATH
export CTP_BRANCH_NAME=develop
export CTP_SKIP_UPDATE=0
EOF
  "

  if [ "$user" == "shell" ]; then
    sudo -u "$user" bash -c "
      cat <<EOF >> $workdir/.bash_profile
#[shell] ENV
export init_path=$ctp_home/shell/init_path
#CUBRID ENV
export CUBRID=$cubrid_home
export CUBRID_DATABASES=$cubrid_home/databases
export LD_LIBRARY_PATH=$cubrid_home/lib:$cubrid_home/cci/lib:$LD_LIBRARY_PATH
export SHLIB_PATH=$LD_LIBRARY_PATH
export LIBPATH=$LD_LIBRARY_PATH
export PATH=$cubrid_home/bin:/usr/sbin:$PATH
EOF
    "
  fi
}

# Function to configure environment
configure() {
  local user=$1
  debug "configure user=$user" "$LINENO"
  setup_git_repositories "$user"
  setup_environment "$user"
}

# Function to run tests
run_test() {
  debug "run_test()" "$LINENO"
  local user="shell"
  local ctp_home="/home/$user/cubrid-testtools/CTP"
  
  su $user -c "cd '$ctp_home' && ./bin/ctp.sh shell"
  report_test
}

# Function to report test results
report_test() {
  debug "report_test()" "$LINENO"
  local user="shell"
  local ctp_home="/home/$user/cubrid-testtools/CTP"
  local feedback_file="$ctp_home/result/shell/current_runtime_logs/feedback.log"
  local test_log="$ctp_home/result/shell/current_runtime_logs/test_local.log"
  local report_file="$ctp_home/result/shell/current_runtime_logs/failure_report.log"
  
  # need to fix
  # Remove existing report file if it exists
  [ -f "$report_file" ] && rm "$report_file"

  # Check if there are any NOK cases
  if ! grep -q "\[NOK\]:" "$feedback_file"; then
    echo "All tests completed successfully."
    return 0
  fi

  # Extract and print information about NOK cases
  while IFS= read -r nok_line; do
    {
      echo "=== Failed Test Case Information ==="
      echo "$nok_line"
      
      # Extract test case path
      local test_case=$(echo "$nok_line" | awk '{print $2}')
      local escaped_test_case=$(echo "$test_case" | sed 's/[\/]/\\\//g')
      
      # Print execution log for the test case
      echo "=== Test Execution Detailed Log ==="
      awk -v tc="$escaped_test_case" '
        /\[TESTCASE\] '"$escaped_test_case"'/ {
          f=1
          next
        }
        /\[TESTCASE\]/ {
          if(f==1) f=0
        }
        f==1 && /\[INFO\] TEST START/,/\[INFO\] TEST STOP/ {
          print
        }
      ' "$test_log"
      echo "================================"
    } >> "$report_file"
  done < <(grep "\[NOK\]:" "$feedback_file")
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
    test)
      run_test
      ;;
    *)
      echo "Unknown role: $role. Use 'controller', 'worker' or 'test'."
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
