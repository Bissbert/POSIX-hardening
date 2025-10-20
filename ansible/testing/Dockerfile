# Dockerfile for Ansible Target Testing
# Simulates a Debian-based target system for hardening

FROM debian:12-slim

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install SSH server and other required packages
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    python3 \
    python3-apt \
    systemd \
    systemd-sysv \
    iptables \
    rsyslog \
    auditd \
    libpam-pwquality \
    procps \
    net-tools \
    iproute2 \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Create SSH directory and configure SSH
RUN mkdir -p /var/run/sshd /root/.ssh && \
    chmod 700 /root/.ssh

# Create test user with sudo privileges
RUN useradd -m -s /bin/bash -G sudo ansible && \
    echo "ansible:ansible" | chpasswd && \
    mkdir -p /home/ansible/.ssh && \
    chmod 700 /home/ansible/.ssh && \
    chown -R ansible:ansible /home/ansible/.ssh

# Allow passwordless sudo for ansible user
RUN echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible && \
    chmod 440 /etc/sudoers.d/ansible

# Configure SSH for testing
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Copy SSH public key (will be mounted at runtime)
COPY authorized_keys /root/.ssh/authorized_keys
COPY authorized_keys /home/ansible/.ssh/authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys /home/ansible/.ssh/authorized_keys && \
    chown ansible:ansible /home/ansible/.ssh/authorized_keys

# Enable systemd
RUN systemctl enable ssh rsyslog

# Expose SSH port
EXPOSE 22

# Start systemd (required for full system simulation)
CMD ["/lib/systemd/systemd"]
