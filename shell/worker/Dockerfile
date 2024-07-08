FROM rockylinux:8

LABEL Description="This is a [shell] test environment image for CUBRID"

# Install required packages
RUN yum install -y epel-release
RUN yum install -y git procps-ng wget which sudo openssh-server openssh-clients java-1.8.0-openjdk-devel 
RUN yum install -y dos2unix lcov bc expect diffutils

RUN ssh-keygen -A
RUN sudo sed -i 's/^account.*pam_nologin.so/#&/' /etc/pam.d/sshd
RUN sudo /usr/sbin/sshd

# Add a user for running tests
RUN useradd -ms /bin/bash shell && \
    echo 'shell:shell' | chpasswd && \
    echo 'shell ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod 775 /entrypoint.sh

# Switch to the new user
USER shell
ENV USER=shell
WORKDIR /home/shell

# Set up environment variables for GitHub credentials
ARG GITHUB_TOKEN
ARG BRANCH

# Clone the repositories
RUN git clone --depth 1 -b ${BRANCH} https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testtools.git && \
    cp -rf /home/shell/cubrid-testtools/CTP /home/shell
RUN git clone --depth 1 -b ${BRANCH} https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testcases-private-ex.git
RUN git clone --depth 1 -b ${BRANCH} https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testcases.git

# Set up Common ENV
ENV JAVA_HOME=/usr/lib/jvm/java

# Set up CTP
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


ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
