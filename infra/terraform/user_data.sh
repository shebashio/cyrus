#!/bin/bash

# Update system
apt-get update
apt-get upgrade -y

# Install SSM Agent (required for Session Manager)
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

# Install useful tools
apt-get install -y \
    curl \
    wget \
    vim \
    git \
    htop \
    net-tools \
    unzip

# Create a directory for application
mkdir -p /opt/app
chown ubuntu:ubuntu /opt/app

# Log the completion
echo "User data script completed at $(date)" >> /var/log/user-data.log