# Cyrus CLI Linux Server Deployment Guide

This guide covers deploying the Cyrus CLI on a Linux server with persistent operation and secure access via Cloudflare Tunnels.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Server Setup](#server-setup)
3. [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup)
4. [Cyrus CLI Installation](#cyrus-cli-installation)
5. [Systemd Service Configuration](#systemd-service-configuration)
6. [Security Considerations](#security-considerations)
7. [Monitoring & Maintenance](#monitoring--maintenance)
8. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Components
- **Linux Server**: Ubuntu 20.04+ or Debian 11+ (other distributions work with adjustments)
- **Node.js**: Version 18 or higher
- **Git**: For cloning repositories
- **Cloudflare Account**: With a domain configured
- **Linear Account**: With OAuth application configured
- **Proxy Worker**: Already deployed (see proxy-worker/DEPLOYMENT.md)

### System Requirements
- **RAM**: Minimum 2GB (4GB recommended for multiple repositories)
- **Storage**: 20GB+ (depends on repository sizes)
- **CPU**: 2+ cores recommended
- **Network**: Stable internet connection

## Server Setup

### 1. Update System and Install Dependencies

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y curl wget git build-essential

# Install Node.js 20 (via NodeSource)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install pnpm globally
npm install -g pnpm

# Install Claude CLI globally
npm install -g @anthropic-ai/claude

# Verify installations
node --version      # Should be v20.x.x
pnpm --version      # Should be 8.x.x or higher
claude --version    # Should show Claude CLI version
```

### 2. Create Dedicated User for Cyrus

```bash
# Create cyrus user without login shell
sudo useradd -r -m -d /opt/cyrus -s /bin/bash cyrus

# Create necessary directories
sudo mkdir -p /opt/cyrus/{workspace,logs,config}
sudo chown -R cyrus:cyrus /opt/cyrus

# Switch to cyrus user
sudo -u cyrus bash
```

### 3. Install Cyrus CLI

```bash
# As cyrus user
cd /opt/cyrus

# Install Cyrus CLI globally for the user
npm install -g cyrus-ai

# Verify installation
cyrus --version
```

## Cloudflare Tunnel Setup

### 1. Install Cloudflared

```bash
# Download and install cloudflared
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# Verify installation
cloudflared --version
```

### 2. Authenticate with Cloudflare

```bash
# Login to Cloudflare (opens browser for authentication)
cloudflared tunnel login

# This saves credentials to ~/.cloudflared/cert.pem
```

### 3. Create Tunnel

```bash
# Create a tunnel for Cyrus
cloudflared tunnel create cyrus-cli

# Note the tunnel ID from output
# Example: Created tunnel cyrus-cli with id 6ff42ae2-765d-4adf-8112-31c55c1551ef
```

### 4. Configure Tunnel

Create tunnel configuration at `/opt/cyrus/config/cloudflared.yml`:

```yaml
tunnel: YOUR_TUNNEL_ID
credentials-file: /home/cyrus/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  # Cyrus CLI webhook endpoint (if needed)
  - hostname: cyrus-cli.yourdomain.com
    service: http://localhost:3000
  # Health check endpoint
  - hostname: health.cyrus-cli.yourdomain.com
    service: http://localhost:3001
  # Catch-all rule (required)
  - service: http_status:404
```

### 5. Route DNS

```bash
# Add DNS route for your tunnel
cloudflared tunnel route dns cyrus-cli cyrus-cli.yourdomain.com
cloudflared tunnel route dns cyrus-cli health.cyrus-cli.yourdomain.com
```

## Cyrus CLI Installation

### 1. Configure Cyrus

Create configuration file at `/opt/cyrus/config/cyrus.env`:

```bash
# Linear Configuration
LINEAR_API_KEY=lin_api_YOUR_LINEAR_API_KEY
LINEAR_USER_ID=YOUR_LINEAR_USER_ID

# Anthropic Configuration  
ANTHROPIC_API_KEY=sk-ant-YOUR_ANTHROPIC_KEY

# Proxy Configuration
CYRUS_PROXY_URL=https://cyrus-proxy.pidof.workers.dev
CYRUS_WEBHOOK_URL=https://cyrus-cli.yourdomain.com/webhook

# Workspace Configuration
CYRUS_WORKSPACE_DIR=/opt/cyrus/workspace
CYRUS_LOG_DIR=/opt/cyrus/logs

# Repository Configuration (optional)
CYRUS_DEFAULT_REPO=https://github.com/your-org/your-repo.git
CYRUS_GIT_USER_NAME="Cyrus Bot"
CYRUS_GIT_USER_EMAIL="cyrus@yourdomain.com"

# Feature Flags
CYRUS_AUTO_ASSIGN=true
CYRUS_AUTO_COMMENT=true
CYRUS_DRY_RUN=false

# Performance Settings
CYRUS_MAX_CONCURRENT_ISSUES=3
CYRUS_POLL_INTERVAL=30  # seconds
```

### 2. Create Startup Script

Create `/opt/cyrus/start-cyrus.sh`:

```bash
#!/bin/bash

# Load environment variables
source /opt/cyrus/config/cyrus.env

# Set workspace
cd /opt/cyrus/workspace

# Log startup
echo "[$(date)] Starting Cyrus CLI..." >> /opt/cyrus/logs/cyrus.log

# Start Cyrus with options
exec cyrus start \
  --workspace-dir="$CYRUS_WORKSPACE_DIR" \
  --log-file="/opt/cyrus/logs/cyrus.log" \
  --proxy-url="$CYRUS_PROXY_URL" \
  --webhook-url="$CYRUS_WEBHOOK_URL" \
  --poll-interval="$CYRUS_POLL_INTERVAL" \
  --max-concurrent="$CYRUS_MAX_CONCURRENT_ISSUES" \
  2>&1 | tee -a /opt/cyrus/logs/cyrus.log
```

Make it executable:
```bash
chmod +x /opt/cyrus/start-cyrus.sh
```

## Systemd Service Configuration

### 1. Create Cyrus Service

Create `/etc/systemd/system/cyrus.service`:

```ini
[Unit]
Description=Cyrus Linear Claude Agent
Documentation=https://github.com/ceedaragents/cyrus
After=network.target

[Service]
Type=simple
User=cyrus
Group=cyrus
WorkingDirectory=/opt/cyrus/workspace

# Environment
EnvironmentFile=/opt/cyrus/config/cyrus.env
Environment="NODE_ENV=production"
Environment="NODE_OPTIONS=--max-old-space-size=2048"

# Start command
ExecStart=/opt/cyrus/start-cyrus.sh

# Restart configuration
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

# Logging
StandardOutput=append:/opt/cyrus/logs/cyrus.log
StandardError=append:/opt/cyrus/logs/cyrus-error.log

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/cyrus

[Install]
WantedBy=multi-user.target
```

### 2. Create Cloudflared Service

Create `/etc/systemd/system/cloudflared.service`:

```ini
[Unit]
Description=Cloudflare Tunnel for Cyrus
After=network.target cyrus.service
Wants=cyrus.service

[Service]
Type=simple
User=cyrus
Group=cyrus
ExecStart=/usr/bin/cloudflared tunnel --config /opt/cyrus/config/cloudflared.yml run
Restart=always
RestartSec=5

StandardOutput=append:/opt/cyrus/logs/cloudflared.log
StandardError=append:/opt/cyrus/logs/cloudflared-error.log

[Install]
WantedBy=multi-user.target
```

### 3. Enable and Start Services

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable services to start on boot
sudo systemctl enable cyrus.service
sudo systemctl enable cloudflared.service

# Start services
sudo systemctl start cyrus.service
sudo systemctl start cloudflared.service

# Check status
sudo systemctl status cyrus.service
sudo systemctl status cloudflared.service
```

## Security Considerations

### 1. Firewall Configuration

```bash
# Install ufw if not present
sudo apt install -y ufw

# Configure firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 443/tcp  # For HTTPS if needed

# Enable firewall
sudo ufw enable
```

### 2. SSH Key Authentication

```bash
# Generate SSH key for Git operations
sudo -u cyrus ssh-keygen -t ed25519 -C "cyrus@yourdomain.com" -f /opt/cyrus/.ssh/id_ed25519

# Add to GitHub/GitLab deploy keys
cat /opt/cyrus/.ssh/id_ed25519.pub
```

### 3. Secrets Management

```bash
# Restrict config file permissions
sudo chmod 600 /opt/cyrus/config/cyrus.env
sudo chown cyrus:cyrus /opt/cyrus/config/cyrus.env

# Use systemd credentials (optional, more secure)
sudo systemctl edit cyrus.service
# Add under [Service]:
# LoadCredential=linear-api-key:/etc/cyrus/linear-api-key
```

### 4. Log Rotation

Create `/etc/logrotate.d/cyrus`:

```
/opt/cyrus/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 cyrus cyrus
    sharedscripts
    postrotate
        systemctl reload cyrus.service > /dev/null 2>&1 || true
    endscript
}
```

## Monitoring & Maintenance

### 1. Health Check Script

Create `/opt/cyrus/health-check.sh`:

```bash
#!/bin/bash

# Check if Cyrus service is running
if systemctl is-active --quiet cyrus.service; then
    echo "✓ Cyrus service is running"
else
    echo "✗ Cyrus service is not running"
    exit 1
fi

# Check if Cloudflared is running
if systemctl is-active --quiet cloudflared.service; then
    echo "✓ Cloudflared tunnel is running"
else
    echo "✗ Cloudflared tunnel is not running"
    exit 1
fi

# Check disk space
DISK_USAGE=$(df /opt/cyrus | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "⚠ Disk usage is high: ${DISK_USAGE}%"
fi

# Check recent errors
ERROR_COUNT=$(tail -n 100 /opt/cyrus/logs/cyrus-error.log 2>/dev/null | grep -c ERROR || echo 0)
if [ $ERROR_COUNT -gt 0 ]; then
    echo "⚠ Found $ERROR_COUNT errors in recent logs"
fi

echo "Health check completed at $(date)"
```

### 2. Monitoring with Prometheus (Optional)

Create `/opt/cyrus/metrics-exporter.js`:

```javascript
const express = require('express');
const fs = require('fs');
const app = express();

app.get('/metrics', (req, res) => {
  // Read Cyrus metrics
  const metrics = {
    cyrus_up: systemctl('is-active', 'cyrus.service') === 'active' ? 1 : 0,
    cyrus_issues_processed: getProcessedIssues(),
    cyrus_errors_total: getErrorCount(),
  };
  
  // Format as Prometheus metrics
  let output = '';
  for (const [key, value] of Object.entries(metrics)) {
    output += `${key} ${value}\n`;
  }
  
  res.type('text/plain');
  res.send(output);
});

app.listen(9090);
```

### 3. Automated Backups

Create `/opt/cyrus/backup.sh`:

```bash
#!/bin/bash

BACKUP_DIR="/backup/cyrus"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup configuration
tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" /opt/cyrus/config/

# Backup workspace (excluding git objects)
tar -czf "$BACKUP_DIR/workspace_$DATE.tar.gz" \
  --exclude='.git/objects' \
  /opt/cyrus/workspace/

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
```

Add to crontab:
```bash
# Daily backup at 2 AM
0 2 * * * /opt/cyrus/backup.sh
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Cyrus Service Won't Start

```bash
# Check logs
sudo journalctl -u cyrus.service -n 50

# Verify environment variables
sudo -u cyrus env | grep CYRUS

# Test manual start
sudo -u cyrus /opt/cyrus/start-cyrus.sh
```

#### 2. Cloudflare Tunnel Connection Issues

```bash
# Check tunnel status
cloudflared tunnel info cyrus-cli

# Test tunnel connectivity
cloudflared tunnel run cyrus-cli

# Check DNS resolution
nslookup cyrus-cli.yourdomain.com
```

#### 3. Linear API Connection Issues

```bash
# Test Linear API key
curl -H "Authorization: Bearer $LINEAR_API_KEY" \
  https://api.linear.app/graphql \
  -d '{"query":"{ viewer { id email }}"}'

# Check network connectivity
ping api.linear.app
```

#### 4. High Memory Usage

```bash
# Check memory usage
free -h
ps aux | grep cyrus

# Adjust Node.js memory limit in service file
# Environment="NODE_OPTIONS=--max-old-space-size=4096"

# Restart service
sudo systemctl restart cyrus.service
```

#### 5. Git Authentication Issues

```bash
# Check SSH key
sudo -u cyrus ssh -T git@github.com

# Configure Git credentials
sudo -u cyrus git config --global user.name "Cyrus Bot"
sudo -u cyrus git config --global user.email "cyrus@yourdomain.com"
```

### Log Locations

- **Cyrus Logs**: `/opt/cyrus/logs/cyrus.log`
- **Cyrus Errors**: `/opt/cyrus/logs/cyrus-error.log`
- **Cloudflared Logs**: `/opt/cyrus/logs/cloudflared.log`
- **System Logs**: `journalctl -u cyrus.service`

### Performance Tuning

```bash
# Increase file descriptor limits
echo "cyrus soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "cyrus hard nofile 65536" | sudo tee -a /etc/security/limits.conf

# Optimize Git for large repositories
git config --global core.preloadindex true
git config --global core.fscache true
git config --global gc.auto 256
```

## Maintenance Commands

### Service Management

```bash
# Start services
sudo systemctl start cyrus.service
sudo systemctl start cloudflared.service

# Stop services
sudo systemctl stop cyrus.service
sudo systemctl stop cloudflared.service

# Restart services
sudo systemctl restart cyrus.service
sudo systemctl restart cloudflared.service

# View logs
sudo journalctl -u cyrus.service -f
sudo journalctl -u cloudflared.service -f

# Check service status
sudo systemctl status cyrus.service
sudo systemctl status cloudflared.service
```

### Updates

```bash
# Update Cyrus CLI
sudo -u cyrus npm update -g cyrus-ai

# Update system packages
sudo apt update && sudo apt upgrade -y

# Update Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
```

### Monitoring

```bash
# Watch service status
watch -n 5 'systemctl status cyrus cloudflared'

# Monitor logs
tail -f /opt/cyrus/logs/*.log

# Check resource usage
htop -u cyrus
```

## Support and Resources

- **Cyrus Documentation**: [GitHub Repository](https://github.com/ceedaragents/cyrus)
- **Cloudflare Tunnels**: [Official Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- **Linear API**: [Developer Documentation](https://developers.linear.app)
- **Anthropic Claude**: [API Documentation](https://docs.anthropic.com)

## Security Checklist

- [ ] Firewall configured and enabled
- [ ] SSH key authentication only
- [ ] Secrets stored securely with restricted permissions
- [ ] Regular security updates installed
- [ ] Log rotation configured
- [ ] Backup strategy implemented
- [ ] Monitoring and alerting set up
- [ ] Resource limits configured
- [ ] Network access restricted to necessary endpoints only

## Next Steps

1. **Test the deployment** by creating a test issue in Linear
2. **Monitor logs** for the first few hours
3. **Set up alerting** for service failures
4. **Document any customizations** for your team
5. **Plan regular maintenance windows** for updates

---

*Last updated: January 2025*
*Version: 1.0.0*