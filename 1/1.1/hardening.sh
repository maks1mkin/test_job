#!/bin/bash


log_info() { echo "[INFO] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }

# check root 
if [[ $EUID -ne 0 ]]; then
   log_error "Need to run as sudo(root user)"
   exit 1
fi

# parameters  
SSH_PORT=${SSH_PORT:-2222}
ADMIN_USER=${ADMIN_USER:-maksimkin}
SSH_KEY_PATH=${SSH_KEY_PATH:-""}

# fail2ban parameters
FAIL2BAN_BANTIME=${FAIL2BAN_BANTIME:-3600}
FAIL2BAN_FINDTIME=${FAIL2BAN_FINDTIME:-600}
FAIL2BAN_MAXRETRY=${FAIL2BAN_MAXRETRY:-3}
FAIL2BAN_SSH_BANTIME=${FAIL2BAN_SSH_BANTIME:-7200}
FAIL2BAN_EMAIL=${FAIL2BAN_EMAIL:-"admin@maksimtech.com"}

# ssh security parameters
SSH_MAX_AUTH_TRIES=${SSH_MAX_AUTH_TRIES:-3}
SSH_MAX_SESSIONS=${SSH_MAX_SESSIONS:-2}
SSH_CLIENT_ALIVE_INTERVAL=${SSH_CLIENT_ALIVE_INTERVAL:-300}
SSH_CLIENT_ALIVE_COUNT_MAX=${SSH_CLIENT_ALIVE_COUNT_MAX:-2}

# automatic updates parameters
AUTO_REBOOT=${AUTO_REBOOT:-false}
AUTO_REBOOT_TIME=${AUTO_REBOOT_TIME:-"03:00"}

log_info "=== Starting Ubuntu server configuration ==="

# system update
log_info "[1/8] Updating system..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get autoremove -y -qq

# installing required packages
log_info "[2/8] Installing required packages..."
apt-get install -y -qq \
    ufw \
    fail2ban \
    unattended-upgrades \
    apt-listchanges \
    sudo \
    nano \
    htop \
    net-tools

# creating non-root user with sudo
log_info "[3/8] Creating user $ADMIN_USER..."
if ! id "$ADMIN_USER" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
    echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ADMIN_USER"
    chmod 0440 "/etc/sudoers.d/$ADMIN_USER"
    
    # configure SSH keys
    mkdir -p "/home/$ADMIN_USER/.ssh"
    if [[ -n "$SSH_KEY_PATH" ]] && [[ -f "$SSH_KEY_PATH" ]]; then
        cp "$SSH_KEY_PATH" "/home/$ADMIN_USER/.ssh/authorized_keys"
    fi
    chmod 700 "/home/$ADMIN_USER/.ssh"
    chmod 600 "/home/$ADMIN_USER/.ssh/authorized_keys" 2>/dev/null || true
    chown -R "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
    
    log_info "User $ADMIN_USER created successfully"
else
    log_warn "User $ADMIN_USER already exists"
fi

# configure sudo command logging
log_info "[4/8] Configuring sudo command logging..."
cat > /etc/sudoers.d/sudo-logging <<EOF
Defaults    logfile="/var/log/sudo.log"
Defaults    log_input,log_output
Defaults    iolog_dir=/var/log/sudo-io/%{user}
EOF
chmod 0440 /etc/sudoers.d/sudo-logging

#  ssh configuration
log_info "[5/8] Configuring SSH on port $SSH_PORT..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

cat > /etc/ssh/sshd_config <<EOF
# SSH Configuration - Hardened
Port $SSH_PORT
Protocol 2

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security
X11Forwarding no
MaxAuthTries $SSH_MAX_AUTH_TRIES
MaxSessions $SSH_MAX_SESSIONS
ClientAliveInterval $SSH_CLIENT_ALIVE_INTERVAL
ClientAliveCountMax $SSH_CLIENT_ALIVE_COUNT_MAX

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Override defaults
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# allow only specific users
AllowUsers $ADMIN_USER
EOF

# checkaem SSH configuration
sshd -t
if [[ $? -eq 0 ]]; then
    log_info "SSH configuration is valid"
else
    log_error "Error in SSH configuration! Rolling back changes..."
    mv /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
    exit 1
fi

# configure Fail2Ban
log_info "[6/8] Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = $FAIL2BAN_BANTIME
findtime = $FAIL2BAN_FINDTIME
maxretry = $FAIL2BAN_MAXRETRY
destemail = $FAIL2BAN_EMAIL
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = $FAIL2BAN_MAXRETRY
bantime = $FAIL2BAN_SSH_BANTIME
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# configure UFW
log_info "[7/8] Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# allow SSH on custom port
ufw allow "$SSH_PORT/tcp" comment 'SSH'
ufw --force enable
ufw status verbose

# configure automatic updates
log_info "[8/8] Configuring automatic updates..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "$AUTO_REBOOT";
Unattended-Upgrade::Automatic-Reboot-Time "$AUTO_REBOOT_TIME";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

log_info "=== Hardening completed successfully! ==="
log_warn "IMPORTANT: SSH is now running on port $SSH_PORT"
log_warn "IMPORTANT: Root login is disabled, use user $ADMIN_USER"
log_warn "IMPORTANT: Restart SSH: systemctl restart sshd"
log_warn "IMPORTANT: Test connection BEFORE closing current session!"

echo ""
echo "Additional verification commands:"
echo "  - ufw status verbose"
echo "  - fail2ban-client status sshd"
echo "  - tail -f /var/log/sudo.log"
echo "  - systemctl status unattended-upgrades"
