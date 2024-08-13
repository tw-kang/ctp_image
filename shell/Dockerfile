FROM rockylinux:8

LABEL Description="This is a [shell] test environment image for CUBRID"

# Install required packages in a single RUN statement to minimize layers
RUN yum install -y epel-release && \
    yum groupinstall -y "Development Tools" && \
    yum install -y net-tools && \
    yum install -y git vim lsof procps-ng file telnet wget sudo openssh-server openssh-clients java-1.8.0-openjdk-devel && \
    yum install -y dos2unix lcov bc expect && \
    yum clean all && \
    rm -rf /var/cache/yum

# SSH setup and user configuration
RUN ssh-keygen -A && \
    sed -i 's/^account.*pam_nologin.so/#&/' /etc/pam.d/sshd && \
    mkdir -p /var/run/sshd && \
    useradd -ms /bin/bash shell_ctrl && \
    useradd -ms /bin/bash shell && \
    echo 'shell_ctrl:shell_ctrl' | chpasswd && \
    echo 'shell:shell' | chpasswd && \
    echo 'shell_ctrl ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    echo 'shell ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    mkdir -p /home/shell/do_not_delete_core /home/shell/ERROR_BACKUP && \
    chown -R shell:shell /home/shell/do_not_delete_core /home/shell/ERROR_BACKUP && \
    ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime && \
    echo "Asia/Seoul" > /etc/timezone

COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod 775 /entrypoint.sh

# Set up environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-1.8.0
ENV CTP_BRANCH_NAME=develop
ENV CTP_SKIP_UPDATE=0

ENTRYPOINT ["/entrypoint.sh"]
