import os
import sys
import boto3
import requests
import time

# Exact mapping matching your merged deploy.yml env specifications
ALB_ARN = os.getenv("ALB_ARN")
TARGET_GROUP_ARN = os.getenv("TARGET_GROUP_ARN")
EC2_SG_ID = os.getenv("EC2_SECURITY_GROUP_ID")
ALB_DNS = os.getenv("ALB_DNS_NAME")
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
            
            # FIXED: Audit IPv6 structural drift
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

def validate_alb_targets(max_retries=6, delay=20):
    """Polls the ALB target group until targets settle into a HEALTHY state to eliminate race conditions."""
    print("🏥 Testing Load Balancer target pool alignment...")
    if not TARGET_GROUP_ARN:
        send_slack_alert("Target Group Error", "FAILED", "TARGET_GROUP_ARN environment variable is undefined.")
        return False

    # FIXED: Implemented an active polling block to handle container/instance warm-up delays
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
            
            # Extract states for localized execution tracking output
            current_states = [t['TargetHealth']['State'] for t in health_descriptions]
            print(f"⏳ [Attempt {attempt}/{max_retries}]: Pool not yet converged. State matrix: {current_states}. Retrying in {delay}s...")
            time.sleep(delay)

        except Exception as e:
            send_slack_alert("Target Group Runtime API Exception", "FAILED", str(e))
            return False

    # If the loop exhausts, process details for the terminal failures
    last_error_details = []
    for target in unhealthy_targets:
        state = target['TargetHealth']['State']
        reason = target['TargetHealth'].get('Reason', 'Unknown Reason')
        desc = target['TargetHealth'].get('Description', 'No diagnostic description.')
        last_error_details.append(f"Target `{target['Target']['Id']}` is *{state}* due to: {reason} ({desc})")

    error_summary = "\n".join(last_error_details)
    send_slack_alert("ALB Target Status: Unhealthy Target Settled", "FAILED", f"Target pool failed to stabilize. Details:\n{error_summary}")
    return False

def validate_application_readiness(max_retries=3, delay=5):
    """Runs a live synthetic HTTP transaction directly against the public ALB endpoint with micro-retries."""
    print("🌐 Verification processing for external application HTTP readiness...")
    if not ALB_DNS:
        send_slack_alert("DNS Verification Failure", "FAILED", "ALB_DNS_NAME token missing from environment data payload.")
        return False

    url = f"http://{ALB_DNS}"
    
    # FIXED: Added fallback/retry loop to absorb transient network blips or DNS latency
    for attempt in range(1, max_retries + 1):
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                print("✅ Application transaction successful. HTTP 200 OK verified.")
                return True
            else:
                print(f"⚠️ [HTTP Attempt {attempt}/{max_retries}]: Endpoint responded with status: {response.status_code}. Retrying...")
                if attempt < max_retries:
                    time.sleep(delay)
                    continue
                
                error_msg = f"The Load Balancer endpoint resolved but returned an active error. Status Code: {response.status_code} (Potential application server crash or 502/504 edge exception)"
                send_slack_alert("Application Readiness: Edge Dynamic Error", "FAILED", error_msg)
                return False
                
        except requests.exceptions.RequestException as e:
            print(f"⚠️ [HTTP Attempt {attempt}/{max_retries}]: Network socket connection failed. Error: {e}")
            if attempt < max_retries:
                time.sleep(delay)
                continue
                
            error_msg = f"Unable to establish network connection socket to ALB endpoint URL ({url}). Infrastructure Routing Failure: {e}"
            send_slack_alert("Application Readiness: Edge Host Unreachable", "FAILED", error_msg)
            return False

def main():
    print("🚀 Running post-apply continuous verification routine...")
    
    # Run tests sequentially. If one fails, exit immediately to prevent alert fatigue.
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