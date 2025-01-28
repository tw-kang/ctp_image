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
  local feedback_file="$result_dir/feedback.log"
  local xml_file="$xml_output/TEST-shell.xml"
  local github_base_url="https://github.com/CUBRID/cubrid-testcases-private-ex/blob/develop"
  local test_base_dir="/home/shell"
  
  # Validate input
  if [ ! -f "$feedback_file" ]; then
    debug "feedback.log not found in $result_dir" "$LINENO"
    return 1
  fi

  # Prepare output directory and file
  mkdir -p "$xml_output"
  rm -f "$xml_file"

  # Initialize XML file
  cat > "$xml_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="shell">
EOF

  # Test case tracking variables
  local current_test=""
  local current_time=""
  local console_output=""
  local in_console_section=false
  local test_result=""

  # Process feedback.log line by line
  while IFS= read -r line; do
    case "$line" in
      # Match NOK test case start
      *"[NOK]:"*)
        # Write previous test case if exists
        if [ -n "$current_test" ] && [ -n "$current_time" ]; then
          # Remove duplicate prefix for GitHub link
          local github_path=$(echo "$current_test" | sed 's/cubrid-testcases-private-ex\/shell/shell/')
          local github_link="$github_base_url/$github_path"
          cat >> "$xml_file" << EOF
    <testcase name="$current_test" time="$current_time">
      <failure message="Test failed - $github_link"><![CDATA[$test_result

============================= CONSOLE OUTPUT =============================
$console_output]]></failure>
    </testcase>
EOF
        fi
        
        # Extract new test case information
        current_test=$(echo "$line" | sed -n 's/.*\[NOK\]:.*\(cubrid-testcases-private-ex\/shell\/.*\.sh\).*/\1/p')
        # Get result file path with absolute path
        local result_file_path="$test_base_dir/$current_test"
        result_file_path="${result_file_path%.sh}.result"
        
        debug "Looking for result file: $result_file_path" "$LINENO"
        if [ -f "$result_file_path" ]; then
          test_result=$(cat "$result_file_path")
          debug "Found result file. Content length: ${#test_result}" "$LINENO"
        else
          test_result="$line"
          debug "Result file not found. Using log line instead." "$LINENO"
        fi
        current_time=""
        console_output=""
        in_console_section=false
        ;;
      
      # Match execution time
      *"----"*"time="*)
        if [ -n "$current_test" ]; then
          current_time=$(echo "$line" | sed -n 's/.*time=\([0-9]*\).*/\1/p')
        fi
        ;;
      
      # Match console output section start
      *"============================= CONSOLE OUTPUT ============================="*)
        in_console_section=true
        ;;
      
      # Match section end markers
      *"[TEST STOP]"* | *"[INFO] TEST STOP"*)
        console_output+="$line"$'\n'
        in_console_section=false
        ;;
      
      # Collect console output
      *)
        if [ "$in_console_section" = true ] && [ -n "$current_test" ]; then
          console_output+="$line"$'\n'
        fi
        ;;
    esac
  done < "$feedback_file"

  # Write the last test case if exists
  if [ -n "$current_test" ] && [ -n "$current_time" ]; then
    # Remove duplicate prefix for GitHub link
    local github_path=$(echo "$current_test" | sed 's/cubrid-testcases-private-ex\/shell/shell/')
    local github_link="$github_base_url/$github_path"
    cat >> "$xml_file" << EOF
    <testcase name="$current_test" time="$current_time">
      <failure message="Test failed - $github_link"><![CDATA[$test_result

============================= CONSOLE OUTPUT =============================
$console_output]]></failure>
    </testcase>
EOF
  fi

  # Close XML file
  cat >> "$xml_file" << EOF
  </testsuite>
</testsuites>
EOF

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
