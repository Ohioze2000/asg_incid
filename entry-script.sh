#!/bin/bash
# Update your package index
sudo apt-get update
#Install required packages
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release -y
#Add Docker’s official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
#Set up the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
#Update the package index again
sudo apt-get update
#Install unzip
sudo apt-get install unzip
#Install Docker Engine
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
#Allow your user to run Docker without sudo
sudo usermod -aG docker ubuntu
#Pull webcontent from github repository
wget https://github.com/Ohioze2000/estate-agency/raw/refs/heads/main/estate-agency.zip
#Unzip the web content
unzip estate-agency.zip
#CD to estate-agency
cd estate-agency
#Build docker image
sudo docker build -t estate-agency .
#Run docker container
sudo docker run -d -p 80:80 estate-agency
#CloudWatch Agent Installation
echo "Starting CloudWatch Agent installation..."
#Download the CloudWatch Agent package
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb
#Install the CloudWatch Agent
sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb
#Clean up the downloaded package
rm /tmp/amazon-cloudwatch-agent.deb

echo "CloudWatch Agent installed."

#CloudWatch Agent Configuration

cat <<'EOF' | sudo tee /opt/aws/amazon-cloudwatch-agent/bin/config.json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "metrics_collected": {
      "cpu": {
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ],
        "totalcpu": true
      },
      "disk": {
        "metrics_collection_interval": 60,
        "resources": [
          "/"
        ],
        "measurement": [
          "used_percent",
          "inodes_free"
        ]
      },
      "mem": {
        "metrics_collection_interval": 60,
        "measurement": [
          "mem_used_percent"
        ]
      },
      "swap": {
        "metrics_collection_interval": 60,
        "measurement": [
          "swap_used_percent"
        ]
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "InstanceName": "${aws:InstanceName}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "/ec2/cloud-init-output",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/ec2/nginx/access",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/ec2/nginx/error",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          }
          # Add more log files here, e.g., for your specific application
          # {
          #   "file_path": "/path/to/your/app.log",
          #   "log_group_name": "/ec2/your-app-name",
          #   "log_stream_name": "{instance_id}",
          #   "retention_in_days": 7
          # }
        ]
      }
    },
    "log_stream_name": "{instance_id}"
  }
}
EOF

echo "CloudWatch Agent configuration created."

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s

echo "CloudWatch Agent started."

echo "Instance setup complete."

#