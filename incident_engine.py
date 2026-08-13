import os
import json
import boto3
import urllib3
import time
from datetime import datetime, timedelta

# AWS SDK connections
cloudwatch = boto3.client('cloudwatch')
logs = boto3.client('logs')
elbv2 = boto3.client('elbv2')
ssm = boto3.client('ssm')
autoscaling = boto3.client('autoscaling')

http = urllib3.PoolManager()

# Lambda Environment Configuration
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
GITHUB_REPO = os.getenv("GITHUB_REPO")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
TARGET_GROUP_ARN = os.getenv("TARGET_GROUP_ARN")
ASG_NAME = os.getenv("ASG_NAME")
ENV_PREFIX = os.getenv("ENV_PREFIX", "prod")

def lambda_handler(event, context):
    try:
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = sns_message.get('AlarmName', 'Unknown-Alarm')
        alarm_description = sns_message.get('AlarmDescription', 'No description provided.')
        new_state = sns_message.get('NewStateValue', 'ALARM')
        reason = sns_message.get('NewStateReason', 'Threshold breached.')
        
        dimensions = {d['name']: d['value'] for d in sns_message.get('Trigger', {}).get('Dimensions', [])}
        asg_name = dimensions.get('AutoScalingGroupName', ASG_NAME)

        if new_state != 'ALARM':
            return {"status": "SKIPPED", "reason": f"Ignored non-alarm state shift: {new_state}"}

        # Telemetry & Diagnostics
        alb_diagnostics = gather_alb_telemetry()
        recent_logs = analyze_cloudwatch_error_logs()
        deploy_version, commit_msg = fetch_latest_gitops_deployment()

        # Root cause assessment
        suspected_rc, severity = correlate_root_cause(alarm_name, alb_diagnostics, recent_logs)

        # In-Place / Scale-Out Auto Remediation Execution
        remediation_triggered = evaluate_auto_remediation(alarm_name, asg_name, alb_diagnostics)

        # ChatOps Slack Report Delivery
        dispatch_slack_report(
            alarm_name=alarm_name,
            description=alarm_description,
            severity=severity,
            version=deploy_version,
            commit=commit_msg,
            root_cause=suspected_rc,
            alb_metrics=alb_diagnostics,
            log_summary=recent_logs,
            remediation=remediation_triggered
        )
        
        return {"status": "SUCCESS", "alarm_processed": alarm_name}

    except Exception as e:
        print(f"❌ Error in Incident Engine: {str(e)}")
        raise e

def gather_alb_telemetry():
    telemetry = {"healthy_hosts": 0, "unhealthy_hosts": 0, "unhealthy_instance_ids": []}
    tg_arn = TARGET_GROUP_ARN
    try:
        if not tg_arn:
            return telemetry
        
        health_resp = elbv2.describe_target_health(TargetGroupArn=tg_arn)
        for target in health_resp['TargetHealthDescriptions']:
            state = target['TargetHealth']['State']
            target_id = target['Target']['Id']
            if state == 'healthy':
                telemetry['healthy_hosts'] += 1
            elif state == 'unhealthy':
                telemetry['unhealthy_hosts'] += 1
                telemetry['unhealthy_instance_ids'].append(target_id)
                
        return telemetry
    except Exception as e:
        print(f"Telemetry warning: {e}")
        return telemetry

def analyze_cloudwatch_error_logs():
    try:
        log_group = "/ec2/nginx/error"
        query = "fields @timestamp, @message | filter @message like /error|critical|502|Fatal/ | sort @timestamp desc | limit 3"
        
        start_query = logs.start_query(
            logGroupName=log_group,
            startTime=int((datetime.utcnow() - timedelta(minutes=15)).timestamp()),
            endTime=int(datetime.utcnow().timestamp()),
            queryString=query
        )
        
        for _ in range(10):
            res = logs.get_query_results(queryId=start_query['queryId'])
            if res['status'] == 'Complete':
                return [r[1]['value'] for r in res['results']] if res['results'] else ["No recent stack traces isolated."]
            time.sleep(1)
        return ["CloudWatch query timeout."]
    except Exception as e:
        return [f"Log stream read skipped: {str(e)}"]

def fetch_latest_gitops_deployment():
    if not GITHUB_REPO or not GITHUB_TOKEN:
        return "Unknown-V1", "Missing GitHub credentials."
    try:
        url = f"https://api.github.com/repos/{GITHUB_REPO}/commits?per_page=1"
        headers = {
            "Authorization": f"token {GITHUB_TOKEN}",
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "AWS-Lambda-Incident-Engine"
        }
        resp = http.request('GET', url, headers=headers, timeout=4.0)
        if resp.status == 200:
            data = json.loads(resp.data.decode('utf-8'))
            return data[0]['sha'][:7], data[0]['commit']['message']
        return "N/A", f"GitHub API HTTP status: {resp.status}"
    except Exception as e:
        return "N/A", f"Pipeline lookup failed: {str(e)}"

def correlate_root_cause(alarm_name, alb, logs_summary):
    if "TargetGroup" in alarm_name or alb['unhealthy_hosts'] > 0:
        return "Target Pool Failure: Unhealthy backends detected in load balancer route table.", "CRITICAL"
    if "ALB-High-5XX" in alarm_name:
        return "Application Fault: Upstream web server dropping connections or throwing 5xx responses.", "HIGH"
    if "Disk" in alarm_name or "Memory" in alarm_name:
        return "OS Resource Exhaustion: Disk partition or RAM capacity limits breached.", "HIGH"
    if "StatusCheck" in alarm_name:
        return "Hardware/OS Impairment: EC2 instance underlying status check failed.", "CRITICAL"
    return "Undetermined infrastructure variance.", "MEDIUM"

def evaluate_auto_remediation(alarm_name, asg_name, alb):
    """Executes SSM commands for OS metrics or ASG scaling for traffic/unhealthy hosts."""
    
    # 1. OS Metric Cleanup Remediation (Memory/Disk) via SSM RunCommand
    if "HighDiskUsage" in alarm_name or "HighMemoryUsage" in alarm_name:
        try:
            # Query targets registered under ASG
            asg_resp = autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])
            instance_ids = [
                i['InstanceId'] for i in asg_resp['AutoScalingGroups'][0]['Instances'] 
                if i['LifecycleState'] == 'InService'
            ]
            
            if not instance_ids:
                return "⚠️ Remediation skipped: No InService instances found in Auto Scaling Group."

            # Command: Clean Docker artifacts, rotate system logs, drop inactive caches
            cleanup_cmd = (
                "sudo docker system prune -af --volumes && "
                "sudo journalctl --vacuum-time=1d && "
                "sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches"
            )
            
            ssm_resp = ssm.send_command(
                InstanceIds=instance_ids,
                DocumentName="AWS-RunShellScript",
                Parameters={'commands': [cleanup_cmd]},
                Comment=f"In-place OS cleanup dispatched by Incident Engine for alarm: {alarm_name}"
            )
            command_id = ssm_resp['Command']['CommandId']
            return f"⚡ **SSM In-Place Remediation Executed**: Garbage collection and cache purge command dispatched to targets `{instance_ids}` (SSM Command ID: `{command_id}`)."

        except Exception as e:
            return f"❌ SSM Remediation Execution Failed: {str(e)}"

    # 2. Scale-Out Remediation for Traffic / Unhealthy Target Isolation
    elif alb['unhealthy_hosts'] > 0 or "5XX" in alarm_name:
        try:
            autoscaling.execute_policy(
                AutoScalingGroupName=asg_name,
                PolicyName='Step-Scaling-Out-Policy-High-Traffic'
            )
            return "✅ **ASG Scale-Out Executed**: Triggered capacity expansion policy to replace impaired workloads."
        except Exception as e:
            return f"❌ ASG Scale-Out execution failed: {str(e)}"

    return "⏭️ No matching auto-remediation rule triggered. Monitoring state."

def dispatch_slack_report(alarm_name, description, severity, version, commit, root_cause, alb_metrics, log_summary, remediation):
    if not SLACK_WEBHOOK_URL:
        return
    
    color = "#dd0000" if severity == "CRITICAL" else "#e67e22"
    log_blocks = "\n".join([f"• `{log[:120]}`" for log in log_summary])

    payload = {
        "attachments": [
            {
                "color": color,
                "title": f"🚨 [{ENV_PREFIX.upper()}] INCIDENT TRIGGERED: {alarm_name}",
                "fields": [
                    {"title": "Severity", "value": f"`{severity}`", "short": True},
                    {"title": "Active Release", "value": f"`{version}`", "short": True},
                    {"title": "Git Commit Context", "value": f"_{commit}_", "short": False},
                    {"title": "Correlated Root Cause", "value": f"*{root_cause}*", "short": False},
                    {"title": "Target Group State", "value": f"🟢 Healthy: {alb_metrics['healthy_hosts']} | 🔴 Unhealthy: {alb_metrics['unhealthy_hosts']}", "short": True},
                    {"title": "Automated Action Status", "value": remediation, "short": False},
                    {"title": "CloudWatch Diagnostic Logs", "value": log_blocks if log_blocks else "No target error dumps found.", "short": False}
                ],
                "footer": "Project Aetheris Observability & Remediation Engine",
                "ts": int(datetime.utcnow().timestamp())
            }
        ]
    }

    try:
        encoded_payload = json.dumps(payload).encode('utf-8')
        http.request(
            'POST',
            SLACK_WEBHOOK_URL,
            body=encoded_payload,
            headers={'Content-Type': 'application/json'},
            timeout=5.0
        )
    except Exception as err:
        print(f"Slack delivery error: {err}")