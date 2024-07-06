FROM rockylinux:8

# Install required packages
RUN yum install -y epel-release
RUN yum install -y git procps-ng wget sudo java-1.8.0-openjdk-devel 
RUN yum install -y dos2unix lcov bc expect

# Add a user for running tests
RUN useradd -ms /bin/bash shell && \
    echo 'shell:cub123!@#' | chpasswd && \
    echo 'shell ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Switch to the new user
USER shell
WORKDIR /home/shell

# Set up environment variables for GitHub credentials
ARG GITHUB_TOKEN

# Clone the repositories
RUN git clone https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testtools.git && \
    cd cubrid-testtools && \
    git checkout develop 

RUN git clone https://${GITHUB_TOKEN}@github.com/tw-kang/cubrid-testcases-private-ex.git && \
    cd cubrid-testcases-private-ex && \
    git checkout develop

RUN git clone https://${GITHUB_TOKEN}@github.com/tw-kang/cubrid-testcases.git && \
    cd cubrid-testcases && \
    git checkout develop

# Set up Common ENV
ENV JAVA_HOME /usr/lib/jvm/java

# Set up CTP
RUN cp -rf /home/shell/cubrid-testtools/CTP /home/shell
ENV CTP_HOME=/home/shell/CTP
ENV PATH=$CTP_HOME/bin:$CTP_HOME/common/script:$PATH
ENV CTP_BRANCH_NAME="develop"
ENV CTP_SKIP_UPDATE=0

# Set up shell ENV
ENV init_path=$CTP_HOME/shell/init_path

# Set up CUBRID ENV
ENV CUBRID=/home/shell/CUBRID
ENV CUBRID_DATABASES=$CUBRID/databases
ENV LD_LIBRARY_PATH=$CUBRID/lib:$CUBRID/cci/lib:$LD_LIBRARY_PATH
ENV SHLIB_PATH=$LD_LIBRARY_PATH
ENV LIBPATH=$LD_LIBRARY_PATH
ENV PATH=$CUBRID/bin:/usr/sbin:$PATH


# Create shell.conf configuration file
#RUN mkdir -p /home/shell/CTP/conf && \
#    echo "
#    default.cubrid.cubrid_port_id=1568
#    default.broker1.BROKER_PORT=10090
#    default.broker1.APPL_SERVER_SHM_ID=10090
#    default.broker2.BROKER_PORT=13091
#    default.broker2.APPL_SERVER_SHM_ID=13091
#    default.ha.ha_port_id=19909
#    scenario=/home/shell/cubrid-testcases-private-ex/shell
#    testcase_exclude_from_file=/home/shell/cubrid-testcases-private-ex/shell/config/daily_regression_test_excluded_list_linux.conf
#    test_continue_yn=false
#    testcase_timeout_in_secs=604800
#    testcase_exclude_by_macro=LINUX_NOT_SUPPORTED
#    testcase_retry_num=0
#    delete_testcase_after_each_execution_yn=false
#    enable_check_disk_space_yn=true
#    owner_email=shell@local
#    feedback_type=file
#    " > /home/shell/CTP/conf/shell.conf

CMD ["/bin/bash"]
