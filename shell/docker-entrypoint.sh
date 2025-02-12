#!/bin/bash

DEBUG=true

USER=""
WORKDIR=""
CTP_HOME=""
CUBRID=""

# Function to print debug messages
debug() {
  [ "$DEBUG" = true ] && echo "[debug] $1 : $2"
}

set_user_workdir() {
  if [ "$1" == "controller" ]; then
    USER="shell_ctrl"
    WORKDIR="/home/shell_ctrl"
    CTP_HOME="$WORKDIR/cubrid-testtools/CTP"
  else
    USER="shell"
    WORKDIR="/home/shell"
    CTP_HOME="$WORKDIR/cubrid-testtools/CTP"
    CUBRID="$WORKDIR/CUBRID"
  fi
}

# Start SSH service and set core dump limits
# start_ssh_and_set_limits() {
#   debug "start_ssh_and_set_limits()" "$LINENO"
#   sudo /usr/sbin/sshd
#   ulimit -c 1
# }

# Function to clone Git repository with sparse checkout
clone_repository() {
  local repo=$2
  local branch=${3:-develop}
  local sparse_dir=${4:-}
  local token=${GITHUB_TOKEN}
  #local url="https://${token:+$token@}github.com/CUBRID/$repo.git"
  local url="https://${token:+$token@}github.com/tw-kang/$repo.git"
  
  if [ -d "$WORKDIR/$repo" ]; then
    sudo -u "$USER" bash -c "cd $WORKDIR/$repo && git fetch origin && git checkout $branch && git pull --depth 1 origin $branch"
  else
    # Sparse checkout
    sudo -u "$USER" bash -c "
      mkdir -p $WORKDIR/$repo &&
      cd $WORKDIR/$repo &&
      git init &&
      git remote add origin $url &&
      git config core.sparseCheckout true &&
      echo '$sparse_dir/*' > .git/info/sparse-checkout &&
      git fetch --depth 1 origin $branch &&
      git checkout $branch
    "
  fi
}

# Git configuration and repository cloning
run_checkout() {
  debug "run_checkout user=$USER" "$LINENO"
  
  sudo -u "$USER" git config --global pack.threads 0
  clone_repository "$USER" "cubrid-testtools" "develop"
  
  if [ "$USER" == "shell" ]; then
    debug "cloning private repositories" "$LINENO"
    clone_repository "$USER" "cubrid-testcases" "develop"
    clone_repository "$USER" "cubrid-testcases-private-ex" "develop" "shell"
    # test code
    debug "remove testcase directories" "$LINENO"
    sudo -u "$USER" bash -c "
      cd $WORKDIR/cubrid-testcases-private-ex/shell && \
      find . -maxdepth 1 -type d ! -name '.' ! -name '_01_utility' ! -name 'config' -exec rm -rf {} \;
    "
  fi
}

# Function to set up environment variables
configure() {
  local user=$USER
  local workdir=$WORKDIR
  local ctp_home=$CTP_HOME
  local cubrid_home=$CUBRID

  # start_ssh_and_set_limits
  sudo /usr/sbin/sshd
  ulimit -c 1

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
  local feedback_file="$ctp_home/result/shell/current_runtime_logs/feedback.log"
  
  su $USER -c "cd '$CTP_HOME' && ./bin/ctp.sh shell"
  
  report_test $TEST_REPORT $feedback_file  
  run_manual_test_result $TEST_REPORT $BASELINE
}

# Function to report test results
report_test() {
  debug "report_test()" "$LINENO"
  local xml_output=$1
  local xml_file=$xml_output/test-${TEST_SUITE}.xml
  local feedback_file=$2

  # Validate input
  if [ ! -f "$feedback_file" ]; then
    debug "feedback.log not found in $CTP_HOME/result/shell/current_runtime_logs" "$LINENO"
    return 1
  fi

  # Get test summary from feedback.log
  local test_category=$(tail -n 10 "$feedback_file" | grep "Test Category:" | awk -F':' '{print $2}')
  local total_case_count=$(tail -n 10 "$feedback_file" | grep "Total Case:" | awk -F':' '{print $2}')
  local total_execution_count=$(tail -n 10 "$feedback_file" | grep "Total Execution Case:" | awk -F':' '{print $2}')
  local total_success_case_count=$(tail -n 10 "$feedback_file" | grep "Total Success Case:" | awk -F':' '{print $2}')
  local total_fail_case_count=$(tail -n 10 "$feedback_file" | grep "Total Fail Case:" | awk -F':' '{print $2}')
  local total_skip_case_count=$(tail -n 10 "$feedback_file" | grep "Total Skip Case:" | awk -F':' '{print $2}')
  local elapse_time=$(tail -n 10 "$feedback_file" | grep "Elapse Time:" | awk -F':' '{print $2}')

  # Prepare output directory and file
  mkdir -p "$xml_output"
  
  # Initialize XML file with header
  cat > "$xml_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="$test_category" tests="$total_case_count" failures="$total_fail_case_count" skipped="$total_skip_case_count" time="$elapse_time">
EOF

  # Test case tracking variables
  local test_name=""
  local test_time=""
  local test_result=""
  local is_timeout=false
  # Define test status constants
  local -r TEST_STATUS_OK="[OK]"
  local -r TEST_STATUS_NOK="[NOK]" 
  local -r TEST_STATUS_SKIP_MACRO="[SKIP_BY_MACRO]"
  local -r TEST_STATUS_SKIP_BUG="[SKIP_BY_BUG]"
  local -r TEST_STATUS_UNKNOWN="[UNKNOWN]"
  local test_status="$TEST_STATUS_UNKNOWN"
  
  # Process feedback.log line by line
  while IFS= read -r line; do
    case "$line" in
      "$TEST_STATUS_OK"*)
        test_name=$(echo "$line" | sed -n 's/.*\[OK\]:.*\(cubrid-testcases-private-ex\/shell\/.*\.sh\).*/\1/p')
        test_time=""
        test_result=""
        test_status="$TEST_STATUS_OK"
        ;;

      "$TEST_STATUS_SKIP_BUG"*)
        test_name=$(echo "$line" | sed -n 's/.*\[SKIP_BY_BUG\].*\(cubrid-testcases-private-ex\/shell\/.*\.sh\).*/\1/p')
        test_time="0"
        test_result=""
        test_status="$TEST_STATUS_SKIP_BUG"
        cat >> "$xml_file" << EOF
    <testcase name="$test_name" time="$test_time">
      <skipped message="$test_status"/>
    </testcase>
EOF
         # Reset variables for next test
          test_name=""
          test_time=""
          test_result=""
          test_status="$TEST_STATUS_UNKNOWN"
        ;;

      "$TEST_STATUS_NOK":*)
        test_name=$(echo "$line" | sed -n 's/.*\[NOK\]:.*\(cubrid-testcases-private-ex\/shell\/.*\.sh\).*/\1/p')
        test_time=""
        test_result=""
        is_timeout=false
        test_status="$TEST_STATUS_NOK"
        ;;

      *": NOK timeout"*)
        is_timeout=true
        test_result+="$line"$'\n'
        ;;  
      
      [0-9][0-9]:[0-9][0-9]:[0-9][0-9]*"time="*)
          [ -n "$test_name" ] && test_time=$(echo "$line" | sed -n 's/.*time=\([0-9]*\).*/\1/p')

          if [ "$test_status" == "$TEST_STATUS_OK" ]; then
              cat >> "$xml_file" << EOF
    <testcase name="$test_name" time="$test_time"/>
EOF
         # Reset variables for next test
          test_name=""
          test_time=""
          test_result=""
          test_status="$TEST_STATUS_UNKNOWN"
          fi

          ;;
            
      "[INFO] TEST STOP"*)
        if [ -n "$test_name" ] && [ -n "$test_time" ]; then
          local failure_msg="Test failed"
          [ "$is_timeout" = true ] && failure_msg="Test failed (timeout)"
          local github_link="$testcases_base_url/$(echo "$test_name" | sed 's/cubrid-testcases-private-ex\/shell/shell/')"
          
          cat >> "$xml_file" << EOF
    <testcase name="$test_name" time="$test_time">
      <failure message="$failure_msg - $github_link">
        <![CDATA[$test_result]]>
      </failure>
    </testcase>
EOF
          # Reset variables for next test
          test_name=""
          test_time=""
          test_result=""
        fi
        ;;
      
      "[TEST STOP]"*)
        # Close XML file and exit loop
        cat >> "$xml_file" << EOF
  </testsuite>
</testsuites>
EOF
        break
        ;;

      *)
        # Collect console output only if we're processing a test case
        [ -n "$test_name" ] && test_result+="$line"$'\n'
        ;;
    esac
  done < "$feedback_file"

  debug "JUnit XML generated: $xml_file" "$LINENO"
}

run_manual_test_result() {
  debug "run_manual_test_result()" "$LINENO"
  local xml_output=$1
  local baseline=$2
  
  cd /
  java -cp $CUBRID/jdbc/cubrid_jdbc.jar:manual_test_result.jar manual_test_result $baseline $xml_output/test-${TEST_SUITE}.xml
  mv $baseline_*.csv $xml_output
  cd -

  debug "csv file generated" "$LINENO"
}

# Main execution function
main() {
  debug "main" "$LINENO"
  # start_ssh_and_set_limits

  local role=$1
  set_user_workdir $role
  case "$role" in
    controller)
      configure
      ;;
    worker)
      configure
      ;;
    checkout)
      run_checkout
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
