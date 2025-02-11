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
  ulimit -c 1
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
    sudo -u "$user" bash -c "cd $workdir/$repo && git fetch origin && git checkout $branch && git pull --depth 1 origin $branch"
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
  local feedback_file="$result_dir/feedback.log"
  local xml_file="$xml_output/TEST-shell.xml"
  # local testcases_root_dir="/home/shell/cubrid-testcases-private-ex"
  # local testcases_remote_url=$(cd $testcases_root_dir && git config --get remote.origin.url)
  # local testcases_hash=$(cd $testcases_root_dir && git rev-parse HEAD)
  # local testcases_base_url="${testcases_remote_url%.git}/blob/$testcases_hash"

  # Validate input
  if [ ! -f "$feedback_file" ]; then
    debug "feedback.log not found in $result_dir" "$LINENO"
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
  
#실패된 테스트 케이스들은 리스트형식의 파일로 저장하여 circleci 에서 다운받을 수 있게.

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
