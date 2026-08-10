import os
import sys
import boto3
import requests
import time
import urllib3

# Suppress SSL warnings only if falling back to raw ALB DNS testing with verify=False
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Environment variables from GitHub Actions runner
ALB_ARN = os.getenv("ALB_ARN")
TARGET_GROUP_ARN = os.getenv("TARGET_GROUP_ARN")
EC2_SG_ID = os.getenv("EC2_SECURITY_GROUP_ID")
ALB_DNS = os.getenv("ALB_DNS_NAME")
DOMAIN_NAME = os.getenv("DOMAIN_NAME")
APP_ENDPOINT = os.getenv("APP_ENDPOINT")
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
ENV_PREFIX = os.getenv("ENV_PREFIX", "prod")

# Initialize AWS SDK clients
elbv2_client = boto3.client("elbv2")
ec2_client = boto3.client("ec2")

def send_slack_alert(title, status, details, color="#ff0000"):
    """Dispatches a custom rich-text block notification directly to Slack."""
    if not SLACK_WEBHOOK_URL:
        print("⚠️ Slack Webhook URL missing. Skipping pipeline notification.")
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
        print(f"Failed to transmit Slack alert: {e}")

def validate_security_groups():
    """Ensures EC2 backend Security Groups do not suffer from public rule drift (IPv4 & IPv6)."""
    print("🕵️‍♂️ Auditing Security Group ingress configurations...")
    if not EC2_SG_ID:
        send_slack_alert("Security Group Mismatch", "FAILED", "EC2_SECURITY_GROUP_ID variable was not passed into the runner environment.")
        return False

    try:
        response = ec2_client.describe_security_groups(GroupIds=[EC2_SG_ID])
        permissions = response['SecurityGroups'][0]['IpPermissions']
        
        for perm in permissions:
            # Audit IPv4 structural drift
            for pair in perm.get('IpRanges', []):
                if pair.get('CidrIp') == '0.0.0.0/0':
                    error_msg = f"Security Group `{EC2_SG_ID}` has open public IPv4 access (0.0.0.0/0)! Compliance baseline breached."
                    send_slack_alert("Security Group Misconfiguration", "FAILED", error_msg)
                    return False
            
            # Audit IPv6 structural drift
            for v6_pair in perm.get('Ipv6Ranges', []):
                if v6_pair.get('CidrIpv6') == '::/0':
                    error_msg = f"Security Group `{EC2_SG_ID}` has open public IPv6 access (::/0)! Compliance baseline breached."
                    send_slack_alert("Security Group Misconfiguration", "FAILED", error_msg)
                    return False

        print("✅ Security Group configuration is structurally sound (No public 0.0.0.0/0 or ::/0 drift).")
        return True
    except Exception as e:
        send_slack_alert("Security Group API Validation Error", "FAILED", str(e))
        return False

def validate_alb_targets(max_retries=10, delay=20):
    """Polls the ALB target group until targets settle into a HEALTHY state to eliminate race conditions."""
    print("🏥 Testing Load Balancer target pool alignment...")
    if not TARGET_GROUP_ARN:
        send_slack_alert("Target Group Error", "FAILED", "TARGET_GROUP_ARN environment variable is undefined.")
        return False

    for attempt in range(1, max_retries + 1):
        try:
            response = elbv2_client.describe_target_health(TargetGroupArn=TARGET_GROUP_ARN)
            health_descriptions = response.get('TargetHealthDescriptions', [])
            
            if not health_descriptions:
                error_msg = "The Application Load Balancer target group pool is completely empty. Nodes failed to register."
                send_slack_alert("ALB Target Status: Empty Pool", "FAILED", error_msg)
                return False

            unhealthy_targets = []
            healthy_count = 0
            
            for target in health_descriptions:
                state = target['TargetHealth']['State']
                if state == 'healthy':
                    healthy_count += 1
                else:
                    unhealthy_targets.append(target)

            if not unhealthy_targets:
                print(f"✅ Target pool health check assertions passed. Live count: {healthy_count}")
                return True
            
            current_states = [t['TargetHealth']['State'] for t in health_descriptions]
            print(f"⏳ [Attempt {attempt}/{max_retries}]: Pool not yet converged. State matrix: {current_states}. Retrying in {delay}s...")
            time.sleep(delay)

        except Exception as e:
            send_slack_alert("Target Group Runtime API Exception", "FAILED", str(e))
            return False

    last_error_details = []
    for target in unhealthy_targets:
        state = target['TargetHealth']['State']
        reason = target['TargetHealth'].get('Reason', 'Unknown Reason')
        desc = target['TargetHealth'].get('Description', 'No diagnostic description.')
        last_error_details.append(f"Target `{target['Target']['Id']}` is *{state}* due to: {reason} ({desc})")

    error_summary = "\n".join(last_error_details)
    send_slack_alert("ALB Target Status: Unhealthy Target Settled", "FAILED", f"Target pool failed to stabilize. Details:\n{error_summary}")
    return False

def validate_application_readiness(max_retries=5, delay=10):
    """Runs a live synthetic HTTP transaction against the Route 53 domain endpoint."""
    print("🌐 Verification processing for external application HTTP readiness...")
    
    # 1. Determine target URL & execution strategy
    headers = {"User-Agent": "Aetheris-Verification-Engine/1.0"}
    verify_ssl = True

    if APP_ENDPOINT:
        url = APP_ENDPOINT if APP_ENDPOINT.startswith("http") else f"https://{APP_ENDPOINT}"
    elif DOMAIN_NAME:
        url = f"https://{DOMAIN_NAME}"
    elif ALB_DNS:
        # Fallback to ALB DNS with SSL verification bypass if custom domain isn't available
        url = f"https://{ALB_DNS}"
        verify_ssl = False
        print("⚠️ Custom domain not supplied. Testing directly against raw ALB DNS (SSL verification bypassed).")
    else:
        send_slack_alert("DNS Verification Failure", "FAILED", "Neither APP_ENDPOINT, DOMAIN_NAME, nor ALB_DNS_NAME token were provided.")
        return False

    print(f"🎯 Target Endpoint: {url}")

    for attempt in range(1, max_retries + 1):
        try:
            response = requests.get(url, headers=headers, timeout=10, verify=verify_ssl)
            if response.status_code in [200, 301, 302]:
                print(f"✅ Application transaction successful. Status Code: {response.status_code}")
                return True
            else:
                print(f"⚠️ [HTTP Attempt {attempt}/{max_retries}]: Endpoint responded with status: {response.status_code}. Retrying...")
                if attempt < max_retries:
                    time.sleep(delay)
                    continue
                
                error_msg = f"The application endpoint resolved but returned status code: {response.status_code}."
                send_slack_alert("Application Readiness: Edge Dynamic Error", "FAILED", error_msg)
                return False
                
        except requests.exceptions.SSLError as e:
            print(f"⚠️ [HTTP Attempt {attempt}/{max_retries}]: SSL Handshake failed: {e}")
            if attempt < max_retries:
                print("⏳ Route 53 or ACM SSL cert propagation may still be settling. Retrying...")
                time.sleep(delay)
                continue
            
            error_msg = f"SSL Certificate Verification failed for {url}. Details: {e}"
            send_slack_alert("Application Readiness: SSL Verification Error", "FAILED", error_msg)
            return False

        except requests.exceptions.RequestException as e:
            print(f"⚠️ [HTTP Attempt {attempt}/{max_retries}]: Network socket connection failed. Error: {e}")
            if attempt < max_retries:
                time.sleep(delay)
                continue
                
            error_msg = f"Unable to establish network connection socket to URL ({url}). Error: {e}"
            send_slack_alert("Application Readiness: Edge Host Unreachable", "FAILED", error_msg)
            return False

def main():
    print("🚀 Running post-apply continuous verification routine...")
    
    if not validate_security_groups():
        print("❌ Security Group verification checks failed. Terminating pipeline block.")
        sys.exit(1)
        
    if not validate_alb_targets():
        print("❌ Target Group convergence failed. Terminating pipeline block.")
        sys.exit(1)
        
    if not validate_application_readiness():
        print("❌ Application readiness handshake failed. Terminating pipeline block.")
        sys.exit(1)

    print("🎉 Infrastructure validation succeeded. Quality gate verified.")
    sys.exit(0)

if __name__ == "__main__":
    main()