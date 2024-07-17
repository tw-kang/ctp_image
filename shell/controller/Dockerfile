# First stage: prepare the base with all dependencies and cloned repositories
FROM rockylinux:8 as builder

# Install required packages in a single RUN statement to minimize layers
RUN yum install -y epel-release && \
    yum install -y git procps-ng wget which sudo openssh-server openssh-clients java-1.8.0-openjdk-devel && \
    yum install -y dos2unix lcov bc expect diffutils && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    ssh-keygen -A && \
    sed -i 's/^account.*pam_nologin.so/#&/' /etc/pam.d/sshd && \
    mkdir -p /var/run/sshd && \
    useradd -ms /bin/bash shell_ctrl && \
    echo 'shell_ctrl:shell_ctrl' | chpasswd && \
    echo 'shell_ctrl ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod 775 /entrypoint.sh

# Switch to the new user
USER shell_ctrl
ENV USER=shell_ctrl
WORKDIR /home/shell_ctrl

# Set up environment variables for GitHub credentials
ARG GITHUB_TOKEN
ARG BRANCH

# Configure Git and clone the repositories
RUN git config --global pack.threads 4 && \
    git clone --depth 1 -b ${BRANCH} https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testtools.git && \
    cp -rf /home/shell_ctrl/cubrid-testtools/CTP /home/shell_ctrl

### Second stage: create final image
FROM rockylinux:8

LABEL Description="This is a [shell] test environment image for CUBRID"

# Copy only the necessary directories from the builder stage
COPY --from=builder / /

RUN chmod 775 /entrypoint.sh

# Switch to the new user
USER shell_ctrl
ENV USER=shell_ctrl
WORKDIR /home/shell_ctrl

# Set up environment variables
RUN echo "#JAVA ENV" >> /home/shell_ctrl/.bash_profile && \
    echo "export JAVA_HOME=/usr/lib/jvm/java-1.8.0" >> /home/shell_ctrl/.bash_profile && \
    echo "#CTP ENV" >> /home/shell_ctrl/.bash_profile && \
    echo "export CTP_HOME=/home/shell_ctrl/CTP" >> /home/shell_ctrl/.bash_profile && \
    echo "export PATH=\$CTP_HOME/bin:\$CTP_HOME/common/script:\$PATH" >> /home/shell_ctrl/.bash_profile && \
    echo "export CTP_BRANCH_NAME=develop" >> /home/shell_ctrl/.bash_profile && \
    echo "export CTP_SKIP_UPDATE=0" >> /home/shell_ctrl/.bash_profile

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
