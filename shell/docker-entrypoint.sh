#!/bin/bash

DEBUG=true

# Function to print debug messages
debug() {
  [ "$DEBUG" = true ] && echo "[debug] $1 : $2"
}

# Initialize system configuration including SSH, users, and environment
init_system() {
  debug "init_system()" "$LINENO"

  dnf install -y coreutils shadow sudo openssh
  dnf clean all
exit
  # Setup SSH configuration
  ssh-keygen -A
  # sed -i 's/^account.*pam_nologin.so/#&/' /etc/pam.d/sshd
  # mkdir -p /var/run/sshd
  
  # Setup users and their home directories
  useradd -ms /bin/bash shell_ctrl
  useradd -ms /bin/bash shell
  echo 'shell_ctrl:shell_ctrl' | chpasswd
  echo 'shell:shell' | chpasswd
  
  # Setup sudo permissions
  echo 'shell_ctrl ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
  echo 'shell ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
  
  # Setup directories and permissions
  mkdir -p /home/shell/do_not_delete_core /home/shell/ERROR_BACKUP
  chown -R shell:shell /home/shell/do_not_delete_core /home/shell/ERROR_BACKUP
  
  # Setup timezone
  ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime
  echo "Asia/Seoul" > /etc/timezone
  
  # Start SSH daemon
  sudo /usr/sbin/sshd
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
run_checkout() {
  local user=$1
  debug "run_checkout user=$user" "$LINENO"
  
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
      cd _01_utility && \
      find . -maxdepth 1 -type d ! -name "." ! -name '_03_start_server' -exec rm -rf {} \;
    "
  fi
}

# Function to set up environment variables
configure() {
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

# Function to run tests
run_test() {
  debug "run_test()" "$LINENO"
  local user="shell"
  local ctp_home="/home/$user/cubrid-testtools/CTP"
  
  # su $user -c "cd '$ctp_home' && ./bin/ctp.sh shell"
  # report_test $TEST_REPORT $ctp_home/result/shell/current_runtime_logs
  report_test /tmp/log $ctp_home/result/shell/current_runtime_logs
}

# Function to report test results
report_test() {
  debug "report_test()" "$LINENO"
  local xml_output=$1
  local result_dir=$2
  #feedback.log : Records the test result for each case, and the result summary.
  local feedback_file="$result_dir/feedback.log"
  #test_status.data : summary for test result.
  local test_status="$result_dir/test_status.data"
  #test_local.log : Records the screen output of CTP tool. It contains the sceen output of each test case.
  local test_log="$result_dir/test_local.log"
  # failure_report.log :report file for ci
  local report_file="$result_dir/failure_report.log"
  
  if [ ! -d "$result_dir" ]; then
    debug "$result_dir not found" "$LINENO"
    echo "$result_dir not found"
    return 1
  fi
  
  if [ ! -f "$test_status" ]; then
    debug "$test_status not found" "$LINENO"
    return 1
  fi

  if [ ! -d "$xml_output" ]; then
    mkdir -p "$xml_output"
  fi

   # for test result collection
    local test_category=""
    local total_cases=""
    local total_execution=""
    local total_success=""
    local total_fail=""
    local total_skip=""

    # for test case information collection
    local TMP_CASES=$(mktemp)
   
  while IFS='=' read -r key value; do
    case "$key" in
      "total_case_count")
        total_cases="$value"
        ;;
      "total_executed_case_count")
        total_execution="$value"
        ;;
      "total_success_case_count")
        total_success="$value"
        ;;
      "total_fail_case_count")
        total_fail="$value"
        ;;
      "total_skip_case_count")
        total_skip="$value"
        ;;
    esac
  done < <(grep -v '^#' "$test_status")
  
  #need to check.
  while IFS= read -r line; do
    if [[ "$line" =~ ^\[OK\]|^\[NOK\]|^\[SKIP_BY_BUG\]|:\ (OK|NOK|SKIP)$ ]]; then
      echo "$line" >> "$TMP_CASES"
    fi
  done < "$feedback_file"
cat $TMP_CASES
  debug "TMP_CASES: $TMP_CASES" "$LINENO"
}

# Main execution function
main() {
  debug "main" "$LINENO"
  init_system

  local role=$1
  case "$role" in
    controller)
      configure "shell_ctrl"
      ;;
    worker)
      configure "shell"
      ;;
    checkout)
      run_checkout "shell"
      ;;
    test)
      run_test
      ;;
    *)
      echo "Unknown role: $role. Use 'controller', 'worker' 'checkout' or 'test'."
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
