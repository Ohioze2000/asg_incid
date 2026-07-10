import os
import json
import boto3
import urllib3
import time
from datetime import datetime, timedelta

# Initialize AWS clients globally for connection reuse
cloudwatch = boto3.client('cloudwatch', region_name='us-east-1')
logs = boto3.client('logs', region_name='us-east-1')
elbv2 = boto3.client('elbv2', region_name='us-east-1')
ssmincidents = boto3.client('ssm-incidents', region_name='us-east-1')

# Initialize HTTP manager globally for connection pooling
http = urllib3.PoolManager()

# Environment configurations passed via Lambda
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
INCIDENT_RESPONSE_PLAN_ARN = os.getenv("INCIDENT_RESPONSE_PLAN_ARN") 
GITHUB_REPO = os.getenv("GITHUB_REPO") 
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN") 
TARGET_GROUP_ARN = os.getenv("TARGET_GROUP_ARN") # FIXED: Passed explicitly from Terraform configuration

def lambda_handler(event, context):
    """Main execution entrance triggered via Amazon SNS Event Mapping."""
    try:
        # 1. Parse incoming CloudWatch Alarm payload from SNS
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = sns_message.get('AlarmName', 'Unknown-Alarm')
        alarm_description = sns_message.get('AlarmDescription', 'No description provided.')
        new_state = sns_message.get('NewStateValue', 'ALARM')
        reason = sns_message.get('NewStateReason', 'Threshold breached.')
        
        # Pull dimensions to target specific components
        dimensions = {d['name']: d['value'] for d in sns_message.get('Trigger', {}).get('Dimensions', [])}
        asg_name = dimensions.get('AutoScalingGroupName', 'prod-webserver-asg')
        
        print(f"🚨 Processing incident pipeline for breached alarm: {alarm_name}")

        if new_state != 'ALARM':
            return {"status": "SKIPPED", "reason": f"Ignored non-alarm state shift: {new_state}"}

        # 2. Automated Diagnostics Layer
        alb_diagnostics = gather_alb_telemetry()
        recent_logs = analyze_cloudwatch_error_logs()
        deploy_version, commit_msg = fetch_latest_gitops_deployment()
        
        # 3. Correlation Engine (Root Cause Assessment)
        suspected_rc, severity = correlate_root_cause(alarm_name, alb_diagnostics, recent_logs)

        # 4. Incident Management Integration (AWS SSM Incident Manager)
        incident_id = create_ssm_incident(alarm_name, suspected_rc, severity)

        # 5. Automated Remediation Guardrails
        remediation_triggered = evaluate_auto_remediation(alarm_name, asg_name, alb_diagnostics)

        # 6. Dispatch Enterprise ChatOps Payload
        dispatch_slack_report(
            alarm_name=alarm_name,
            description=alarm_description,
            incident_id=incident_id,
            severity=severity,
            version=deploy_version,
            commit=commit_msg,
            root_cause=suspected_rc,
            alb_metrics=alb_diagnostics,
            log_summary=recent_logs,
            reremediation=remediation_triggered
        )
        
        return {"status": "SUCCESS", "incident_id": incident_id}

    except Exception as e:
        print(f"❌ Critical failure inside the Incident Response Engine: {str(e)}")
        raise e

def gather_alb_telemetry():
    """Queries the ELBv2 control plane to isolate routing errors and node pools."""
    print("📊 Executing ALB Diagnostic Layer...")
    telemetry = {"healthy_hosts": 0, "unhealthy_hosts": 0, "http_5xx_rate": 0.0}
    
    # FIXED: Prioritize specific target group ARN passed by infrastructure configurations
    tg_arn = TARGET_GROUP_ARN
    
    try:
        if not tg_arn:
            print("Warning: TARGET_GROUP_ARN env variable missing. Falling back to dynamic discovery.")
            tgs = elbv2.describe_target_groups()
            if not tgs['TargetGroups']: return telemetry
            tg_arn = tgs['TargetGroups'][0]['TargetGroupArn']
        
        health_resp = elbv2.describe_target_health(TargetGroupArn=tg_arn)
        for target in health_resp['TargetHealthDescriptions']:
            state = target['TargetHealth']['State']
            if state == 'healthy': telemetry['healthy_hosts'] += 1
            elif state == 'unhealthy': telemetry['unhealthy_hosts'] += 1
            
        return telemetry
    except Exception as e:
        print(f"Warning: Could not fetch ALB data: {e}")
        return telemetry

def analyze_cloudwatch_error_logs():
    """Queries log groups via CloudWatch Insights to find runtime crash dumps."""
    print("📝 Auditing CloudWatch Log Streams for active Stack Traces...")
    try:
        log_group = "/aws/ec2/project-aetheris-apps"
        query = "fields @timestamp, @message | filter @message like /Error|Exception|502|Fatal/ | sort @timestamp desc | limit 3"
        
        start_query = logs.start_query(
            logGroupName=log_group,
            startTime=int((datetime.utcnow() - timedelta(minutes=15)).timestamp()),
            endTime=int(datetime.utcnow().timestamp()),
            queryString=query
        )
        
        # FIXED: Robust pooling loop extension to allow query to complete
        for _ in range(10):
            res = logs.get_query_results(queryId=start_query['queryId'])
            if res['status'] == 'Complete':
                return [results[1]['value'] for results in res['results']] if res['results'] else ["No matching stack traces isolated."]
            elif res['status'] in ['Failed', 'Cancelled']:
                return ["CloudWatch Insights query execution aborted internal lookup."]
            time.sleep(1)
        return ["Timeout: CloudWatch log query did not resolve within threshold limits."]
    except Exception as e:
        return [f"Log stream lookup bypassed or log group unavailable. Info: {str(e)}"]

def fetch_latest_gitops_deployment():
    """Pulls deployment context from the Git history to catch bad code pushes."""
    if not GITHUB_REPO or not GITHUB_TOKEN:
        return "Unknown-V1.0.0", "GitHub API configurations missing."
    try:
        url = f"https://api.github.com/repos/{GITHUB_REPO}/commits?per_page=1"
        headers = {
            "Authorization": f"token {GITHUB_TOKEN}", 
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "AWS-Lambda-Incident-Engine"
        }
        
        # FIXED: Swapped requests for native urllib3 execution
        resp = http.request('GET', url, headers=headers, timeout=4.0)
        if resp.status == 200:
            data = json.loads(resp.data.decode('utf-8'))
            sha = data[0]['sha'][:7]
            msg = data[0]['commit']['message']
            return sha, msg
        return "N/A", f"GitHub API responded with status code: {resp.status}"
    except Exception as e:
        return "N/A", f"Failed to resolve pipeline state metadata: {str(e)}"

def correlate_root_cause(alarm_name, alb, logs_summary):
    """Evaluates telemetry patterns to derive the probable architectural failure vector."""
    if alb['unhealthy_hosts'] > 0 and alb['healthy_hosts'] == 0:
        return "Total Backend Outage: All instances failing ALB target health status check routines.", "CRITICAL"
    if "502" in str(logs_summary) or alb['http_5xx_rate'] > 5.0:
        return "Application Crash Loop: Nginx/App proxy active but returning 502 Bad Gateway exceptions.", "HIGH"
    if "high-cpu" in alarm_name.lower():
        return "Resource Exhaustion: Sudden organic traffic volume spike or runaway computational threads.", "MEDIUM"
    return "Undetermined operational anomaly. Manual intervention requested.", "HIGH"

def create_ssm_incident(alarm_name, root_cause, severity):
    """Establishes an automated operational incident record in AWS Incident Manager."""
    if not INCIDENT_RESPONSE_PLAN_ARN:
        return "MOCK-INCIDENT-4039"
    try:
        response = ssmincidents.start_incident(
            responsePlanArn=INCIDENT_RESPONSE_PLAN_ARN,
            title=f"Auto-Generated Incident: {alarm_name}",
            triggerDetails={
                'source': 'Automated Python Monitoring Layer',
                'timestamp': datetime.utcnow(),
                'rawTriggerMessage': f"Suspected Root Cause: {root_cause} | Urgency Level: {severity}"
            }
        )
        return response['incidentRecordArn'].split('/')[-1]
    except Exception as e:
        print(f"Failed to provision SSM Incident Manager session: {e}")
        return "ERR-INTERNAL-NEW"

def evaluate_auto_remediation(alarm_name, asg_name, alb):
    """Executes automated safe actions based on explicit operational conditions."""
    if alb['unhealthy_hosts'] > 0 or "high-cpu" in alarm_name.lower():
        try:
            asg_client = boto3.client('autoscaling', region_name='us-east-1')
            asg_client.execute_policy(
                AutoScalingGroupName=asg_name,
                PolicyName='Step-Scaling-Out-Policy-High-Traffic'
            )
            return "✅ Scale-Out Remediator Action Injected: Provisioning additional compute capacity to recover node health pool."
        except Exception as e:
            return f"❌ Auto-Remediation policy deployment failed: {e}"
    return "⏭️ No safe auto-remediation rule matched. Awaiting human analysis."

def dispatch_slack_report(alarm_name, description, incident_id, severity, version, commit, root_cause, alb_metrics, log_summary, reremediation):
    """Sends a scannable structural alert directly to the designated engineering Slack channel."""
    if not SLACK_WEBHOOK_URL: 
        print("Warning: SLACK_WEBHOOK_URL environment variable missing.")
        return
    
    color = "#dd0000" if severity == "CRITICAL" else "#e67e22"
    log_blocks = "\n".join([f"• `{log[:100]}`" for log in log_summary])

    payload = {
        "attachments": [
            {
                "color": color,
                "title": f"🚨 INCIDENT ENGAGED: {alarm_name} ({severity})",
                "fields": [
                    {"title": "Incident ID", "value": f"`{incident_id}`", "short": True},
                    {"title": "Active Target Version", "value": f"`{version}`", "short": True},
                    {"title": "Latest Commit Message", "value": f"_{commit}_", "short": False},
                    {"title": "Suspected Root Cause", "value": f"*{root_cause}*", "short": False},
                    {"title": "ALB Node Health", "value": f"🟢 Healthy: {alb_metrics['healthy_hosts']} | 🔴 Unhealthy: {alb_metrics['unhealthy_hosts']}", "short": True},
                    {"title": "Automated Response", "value": reremediation, "short": False},
                    {"title": "Targeted Diagnostic Logs", "value": log_blocks if log_blocks else "No target error dumps found.", "short": False}
                ],
                "footer": "Project Aetheris AI Monitoring & Remediation Daemon",
                "ts": int(datetime.utcnow().timestamp())
            }
        ]
    }
    
    # FIXED: Formatted payloads and added robust exception handling for urllib3 delivery
    try:
        encoded_payload = json.dumps(payload).encode('utf-8')
        response = http.request(
            'POST', 
            SLACK_WEBHOOK_URL, 
            body=encoded_payload, 
            headers={'Content-Type': 'application/json'},
            timeout=5.0
        )
        print(f"Remediation diagnostic dashboard shipped to Slack. HTTP Response Status: {response.status}")
    except Exception as err:
        print(f"Non-blocking failure: Unable to ship diagnostic block payload to Slack endpoint: {err}")