#!/bin/bash
set -euo pipefail

# ==============================================================================
# LOGGING SETUP
# ==============================================================================
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "======================================================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting EC2 User Data Bootstrap Process"
echo "======================================================================"

# Non-interactive apt configuration
export DEBIAN_FRONTEND=noninteractive

# ==============================================================================
# 1. SYSTEM UPDATES & DEPENDENCY INSTALLATION
# ==============================================================================
echo "[INFO] Updating package index and installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    wget

# ==============================================================================
# 2. DOCKER ENGINE INSTALLATION
# ==============================================================================
echo "[INFO] Configuring Docker official repository..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y

echo "[INFO] Installing Docker components..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Grant default Ubuntu user access to Docker daemon
sudo usermod -aG docker ubuntu || true

# ==============================================================================
# 3. APPLICATION CONTAINERIZATION & DEPLOYMENT
# ==============================================================================
echo "[INFO] Fetching web content and building Docker image..."
APP_DIR="/opt/estate-agency"
sudo mkdir -p "${APP_DIR}"
cd "${APP_DIR}"

sudo wget -q https://github.com/Ohioze2000/estate-agency/raw/refs/heads/main/estate-agency.zip
sudo unzip -o estate-agency.zip
cd estate-agency

echo "[INFO] Building and starting Docker application container..."
sudo docker build -t estate-agency .
sudo docker run -d --name estate-agency-app --restart always -p 80:80 estate-agency

# ==============================================================================
# 4. CLOUDWATCH AGENT INSTALLATION & STARTUP
# ==============================================================================
echo "[INFO] Installing AWS CloudWatch Agent..."
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb
sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb
rm -f /tmp/amazon-cloudwatch-agent.deb

echo "[INFO] Checking for decoupled CloudWatch configuration..."
CWA_CONFIG_FILE="/opt/aws/amazon-cloudwatch-agent/bin/config.json"

# Option A: Local file rendered via Terraform user_data / templatefile
# Option B: Downloaded dynamically from AWS SSM Parameter Store if file does not exist locally
if [ ! -f "${CWA_CONFIG_FILE}" ]; then
    echo "[WARN] Local config file ${CWA_CONFIG_FILE} not present. Attempting to fetch from SSM..."
    # If using SSM Parameter Store, uncomment line below:
    # sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c ssm:/asg-webserver/cloudwatch-agent-config -s
fi

if [ -f "${CWA_CONFIG_FILE}" ]; then
    echo "[INFO] Starting CloudWatch Agent using ${CWA_CONFIG_FILE}..."
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -c "file:${CWA_CONFIG_FILE}" \
        -s
else
    echo "[WARN] No explicit config file found. Initializing agent with default metrics..."
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -c default \
        -s
fi

echo "======================================================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Instance bootstrap complete!"
echo "======================================================================"