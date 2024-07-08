FROM rockylinux:8

# Install required packages
RUN yum install -y epel-release
RUN yum install -y git procps-ng wget which sudo openssh-server openssh-clients java-1.8.0-openjdk-devel 
RUN yum install -y dos2unix lcov bc expect diffutils

RUN ssh-keygen -A
RUN sudo sed -i 's/^account.*pam_nologin.so/#&/' /etc/pam.d/sshd
RUN sudo /usr/sbin/sshd

# Add a user for running tests
RUN useradd -ms /bin/bash shell_ctrl && \
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

# Clone the repositories
RUN git clone --depth 1 -b ${BRANCH} https://${GITHUB_TOKEN}@github.com/CUBRID/cubrid-testtools.git && \
    cp -rf /home/shell/cubrid-testtools/CTP /home/shell_ctrl

# Set up Common ENV
ENV JAVA_HOME=/usr/lib/jvm/java

# Set up CTP
ENV CTP_HOME=/home/shell_ctrl/CTP
ENV PATH=$CTP_HOME/bin:$CTP_HOME/common/script:$PATH
ENV CTP_BRANCH_NAME="develop"
ENV CTP_SKIP_UPDATE=0


ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
