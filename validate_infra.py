import os
import sys
import boto3
import requests
import time
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

ALB_ARN = os.getenv("ALB_ARN")
TARGET_GROUP_ARN = os.getenv("TARGET_GROUP_ARN")
EC2_SG_ID = os.getenv("EC2_SECURITY_GROUP_ID")
ALB_DNS = os.getenv("ALB_DNS_NAME")
DOMAIN_NAME = os.getenv("DOMAIN_NAME")
APP_ENDPOINT = os.getenv("APP_ENDPOINT")
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
ENV_PREFIX = os.getenv("ENV_PREFIX", "prod")

elbv2_client = boto3.client("elbv2")
ec2_client = boto3.client("ec2")

def send_slack_alert(title, status, details, color="#ff0000"):
    if not SLACK_WEBHOOK_URL:
        print("⚠️ Slack Webhook missing. Skipping notification.")
        return

    payload = {
        "attachments": [
            {
                "color": color,
                "title": f"🚨 [{ENV_PREFIX.upper()}] Quality Gate Failure: {title}",
                "text": f"*Component Status:* {status}\n*Failure Details:* {details}",
                "footer": "Project Aetheris Verification Engine"
            }
        ]
    }
    try:
        requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=5)
    except Exception as e:
        print(f"Failed to send Slack alert: {e}")

def validate_security_groups():
    print("🕵️‍♂️ Auditing Security Group ingress configurations...")
    if not EC2_SG_ID:
        send_slack_alert("Security Group Mismatch", "FAILED", "EC2_SECURITY_GROUP_ID missing.")
        return False

    try:
        response = ec2_client.describe_security_groups(GroupIds=[EC2_SG_ID])
        permissions = response['SecurityGroups'][0]['IpPermissions']
        
        for perm in permissions:
            for pair in perm.get('IpRanges', []):
                if pair.get('CidrIp') == '0.0.0.0/0':
                    send_slack_alert("Security Group Violation", "FAILED", f"SG `{EC2_SG_ID}` has public IPv4 access (0.0.0.0/0).")
                    return False
            for v6_pair in perm.get('Ipv6Ranges', []):
                if v6_pair.get('CidrIpv6') == '::/0':
                    send_slack_alert("Security Group Violation", "FAILED", f"SG `{EC2_SG_ID}` has public IPv6 access (::/0).")
                    return False

        print("✅ Security Group configuration verified.")
        return True
    except Exception as e:
        send_slack_alert("Security Group Validation Error", "FAILED", str(e))
        return False

def validate_alb_targets(max_retries=10, delay=20):
    print("🏥 Checking Target Group health status...")
    if not TARGET_GROUP_ARN:
        send_slack_alert("Target Group Error", "FAILED", "TARGET_GROUP_ARN variable missing.")
        return False

    for attempt in range(1, max_retries + 1):
        try:
            response = elbv2_client.describe_target_health(TargetGroupArn=TARGET_GROUP_ARN)
            health_descriptions = response.get('TargetHealthDescriptions', [])
            
            if not health_descriptions:
                send_slack_alert("Target Pool Empty", "FAILED", "Target group has no registered instances.")
                return False

            unhealthy_targets = [t for t in health_descriptions if t['TargetHealth']['State'] != 'healthy']

            if not unhealthy_targets:
                print(f"✅ Target pool healthy. Count: {len(health_descriptions)}")
                return True
            
            print(f"⏳ [Attempt {attempt}/{max_retries}]: Waiting for target convergence. Retrying in {delay}s...")
            time.sleep(delay)

        except Exception as e:
            send_slack_alert("Target Health API Exception", "FAILED", str(e))
            return False

    send_slack_alert("Target Group Convergence Failure", "FAILED", "Target pool failed to reach healthy state.")
    return False

def validate_application_readiness(max_retries=5, delay=10):
    print("🌐 Verification processing for HTTP endpoint readiness...")
    headers = {"User-Agent": "Aetheris-Verification-Engine/1.0"}
    verify_ssl = True

    if APP_ENDPOINT:
        url = APP_ENDPOINT if APP_ENDPOINT.startswith("http") else f"https://{APP_ENDPOINT}"
    elif DOMAIN_NAME:
        url = f"https://{DOMAIN_NAME}"
    elif ALB_DNS:
        url = f"https://{ALB_DNS}"
        verify_ssl = False
    else:
        send_slack_alert("DNS Resolution Error", "FAILED", "No endpoint URL supplied.")
        return False

    for attempt in range(1, max_retries + 1):
        try:
            response = requests.get(url, headers=headers, timeout=10, verify=verify_ssl)
            if response.status_code in [200, 301, 302]:
                print(f"✅ Application response status code: {response.status_code}")
                return True
            time.sleep(delay)
        except Exception as e:
            if attempt == max_retries:
                send_slack_alert("Endpoint Unreachable", "FAILED", f"URL {url} check failed: {e}")
                return False
            time.sleep(delay)

def main():
    print("🚀 Starting continuous integration quality gate checks...")
    if not validate_security_groups() or not validate_alb_targets() or not validate_application_readiness():
        sys.exit(1)
    print("🎉 All verification checks passed successfully.")
    sys.exit(0)

if __name__ == "__main__":
    main()