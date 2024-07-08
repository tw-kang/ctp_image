FROM rockylinux:8

# Install required packages
RUN yum install -y epel-release
RUN yum install -y git procps-ng wget which sudo openssh-server openssh-clients java-1.8.0-openjdk-devel 
RUN yum install -y dos2unix lcov bc expect diffutils

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
RUN mkdir do_not_delete_core
RUN mkdir ERROR_BACKUP

# Set up shell ENV
ENV init_path=$CTP_HOME/shell/init_path

# Set up CUBRID ENV
ENV CUBRID=/home/shell/CUBRID
ENV CUBRID_DATABASES=$CUBRID/databases
ENV LD_LIBRARY_PATH=$CUBRID/lib:$CUBRID/cci/lib:$LD_LIBRARY_PATH
ENV SHLIB_PATH=$LD_LIBRARY_PATH
ENV LIBPATH=$LD_LIBRARY_PATH
ENV PATH=$CUBRID/bin:/usr/sbin:$PATH

COPY docker-entrypoint.sh /entrypoint.sh
RUN sudo chmod 775 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
