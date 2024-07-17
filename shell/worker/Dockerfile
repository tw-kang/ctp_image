# First stage: prepare the base with all dependencies and cloned repositories
FROM rockylinux:8 as builder

# Install required packages
RUN yum install -y epel-release && \
    yum install -y git procps-ng wget which sudo openssh-server openssh-clients java-1.8.0-openjdk-devel && \
    yum install -y dos2unix lcov bc expect diffutils && \
    yum clean all && \
    rm -rf /var/cache/yum

RUN ssh-keygen -A && \
    sed -i 's/^account.*pam_nologin.so/#&/' /etc/pam.d/sshd && \
    mkdir -p /var/run/sshd

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

### Second stage: create final image
FROM rockylinux:8

LABEL Description="This is a [shell] test environment image for CUBRID"

# Copy the prepared environment from the builder stage
COPY --from=builder / /

RUN chmod 775 /entrypoint.sh 

# Switch to the new user
USER shell
WORKDIR /home/shell

#Set up ENV
RUN echo "#JAVA ENV" >> /home/shell/.bash_profile && \
    echo "export JAVA_HOME=/usr/lib/jvm/java-1.8.0" >> /home/shell/.bash_profile && \
    echo "#CTP ENV" >> /home/shell/.bash_profile && \
    echo "export CTP_HOME=/home/shell/CTP" >> /home/shell/.bash_profile && \
    echo "export PATH=\$CTP_HOME/bin:\$CTP_HOME/common/script:\$PATH" >> /home/shell/.bash_profile && \
    echo "export CTP_BRANCH_NAME=develop" >> /home/shell/.bash_profile && \
    echo "export CTP_SKIP_UPDATE=0" >> /home/shell/.bash_profile && \
    echo "#[shell] ENV" >> /home/shell/.bash_profile && \
    echo "export init_path=\$CTP_HOME/shell/init_path" >> /home/shell/.bash_profile && \
    echo "#CUBRID ENV" >> /home/shell/.bash_profile && \
    echo "export CUBRID=/home/shell/CUBRID" >> /home/shell/.bash_profile && \
    echo "export CUBRID_DATABASES=\$CUBRID/databases" >> /home/shell/.bash_profile && \
    echo "export LD_LIBRARY_PATH=\$CUBRID/lib:\$CUBRID/cci/lib:\$LD_LIBRARY_PATH" >> /home/shell/.bash_profile && \
    echo "export SHLIB_PATH=\$LD_LIBRARY_PATH" >> /home/shell/.bash_profile && \
    echo "export LIBPATH=\$LD_LIBRARY_PATH" >> /home/shell/.bash_profile && \
    echo "export PATH=\$CUBRID/bin:/usr/sbin:\$PATH" >> /home/shell/.bash_profile && \
    mkdir -p /home/shell/do_not_delete_core && \
    mkdir -p /home/shell/ERROR_BACKUP && \
    chown -R shell:shell /home/shell/do_not_delete_core && \
    chown -R shell:shell /home/shell/ERROR_BACKUP


ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
