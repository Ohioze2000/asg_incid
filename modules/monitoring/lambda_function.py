import os
import json
import urllib.request
import logging
import boto3
from datetime import datetime, timezone

# Initialize structured logging engine
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS SDK Client Packages
elbv2 = boto3.client('elbv2')
autoscaling = boto3.client('autoscaling')
ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    logger.info(f"Received raw event payload: {json.dumps(event)}")
    
    # 1. Parse incoming SNS CloudWatch Alarm Metadata
    try:
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = sns_message.get('AlarmName', 'Unknown Alarm')
        new_state = sns_message.get('NewStateValue', 'UNKNOWN')
        reason = sns_message.get('NewStateReason', 'No reason provided.')
        region = sns_message.get('Region', 'us-east-1')
        
        # Extract triggering instance ID from alarm dimensions if present
        trigger_instance_id = None
        for dimension in sns_message.get('Trigger', {}).get('Dimensions', []):
            if dimension.get('name') == 'InstanceId':
                trigger_instance_id = dimension.get('value')
                break

    except Exception as e:
        logger.error(f"Error parsing SNS/CloudWatch payload: {str(e)}")
        return {'statusCode': 400, 'body': 'Invalid event structural format'}

    # Gracefully exit if it's a test or an OK state transition reset
    if new_state != 'ALARM':
        logger.info(f"Ignored non-alarm state shift: {new_state}")
        return {'statusCode': 200, 'body': f"Ignored non-alarm state shift: {new_state}"}

    # 2. Extract context variables provided dynamically by our Terraform module
    slack_webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
    target_group_arn  = os.environ.get('TARGET_GROUP_ARN')
    asg_name          = os.environ.get('ASG_NAME')
    env_prefix        = os.environ.get('ENV_PREFIX', 'production')
    
    # HARD REQUIREMENT CHECK: Alert if webhook URL is missing
    if not slack_webhook_url:
        logger.error("CRITICAL: SLACK_WEBHOOK_URL environment variable is missing or empty!")

    incident_id = f"INC-{context.aws_request_id[:8].upper()}"
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
    remediation_summary = "🔍 *Analysis:* Threshold trigger detected. System instances monitored."
    remediated_instance_id = None

    # 3. INTERCEPT AND ISOLATE FAILING BACKEND INSTANCES
    if target_group_arn and asg_name:
        try:
            # Check target health
            health_response = elbv2.describe_target_health(TargetGroupArn=target_group_arn)
            unhealthy_nodes = [
                target['Target']['Id'] for target in health_response.get('TargetHealthDescriptions', [])
                if target.get('TargetHealth', {}).get('State') == 'unhealthy'
            ]
            
            if unhealthy_nodes:
                remediated_instance_id = unhealthy_nodes[0]
                logger.warning(f"Isolating unhealthy node {remediated_instance_id} from target group {target_group_arn}")
                
                # Command ASG to release instance and immediately provision replacement node
                autoscaling.detach_instances(
                    InstanceIds=[remediated_instance_id],
                    AutoScalingGroupName=asg_name,
                    ShouldDecrementDesiredCapacity=False
                )
                
                # Tag instance for quarantine forensic reviews
                ec2.create_tags(
                    Resources=[remediated_instance_id],
                    Tags=[
                        {'Key': 'Incident_Status', 'Value': 'Quarantined'},
                        {'Key': 'Incident_ID', 'Value': incident_id}
                    ]
                )

                remediation_summary = f"⚡ *AUTOMATED REMEDIATION ENGAGED:* Detached failing instance `{remediated_instance_id}` from production clusters for quarantine."
            else:
                if trigger_instance_id:
                    remediation_summary = f"ℹ️ *Alert Triggered on Host:* `{trigger_instance_id}`. Instance health is passing ALB target checks."
                else:
                    remediation_summary = "ℹ️ *Alert Triggered across ASG group.* Target health checks are currently passing."

        except Exception as err:
            remediation_summary = f"⚠️ *Automated Mitigation Warning:* Could not check target health: {str(err)}"
            logger.error(f"Error executing remediation loop: {str(err)}")

    # 4. Construct Rich Interactive Slack Card Payload Block
    slack_payload = {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"🚨 Incident Response Engine Actioned: {alarm_name}"
                }
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Incident ID:*\n{incident_id}"},
                    {"type": "mrkdwn", "text": f"*Trigger Time:*\n{timestamp}"},
                    {"type": "mrkdwn", "text": f"*Environment:*\n`{env_prefix}`"}
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*CloudWatch Violation Reason:*\n>_{reason}_"
                }
            },
            {"type": "divider"},
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"🛠️ *Remediation Strategy Output:*\n{remediation_summary}"
                }
            }
        ]
    }

    # Dynamically append interactive button if instance was quarantined
    if remediated_instance_id:
        slack_payload["blocks"].extend([
            {"type": "divider"},
            {
                "type": "actions",
                "elements": [
                    {
                        "type": "button",
                        "text": {"type": "plain_text", "text": "Inspect Quarantined Node 🔍"},
                        "url": f"https://{region}.console.aws.amazon.com/ec2/home?region={region}#Instances:search={remediated_instance_id}"
                    }
                ]
            }
        ])

    # 5. Push compiled remediation status payload directly to Slack Webhook
    if slack_webhook_url:
        try:
            encoded_data = json.dumps(slack_payload).encode('utf-8')
            req = urllib.request.Request(
                slack_webhook_url,
                data=encoded_data,
                headers={'Content-Type': 'application/json'}
            )
            with urllib.request.urlopen(req) as response:
                logger.info(f"Slack webhook delivered successfully. Status code: {response.getcode()}")
        except Exception as post_err:
            logger.error(f"Failed to submit message to Slack channel endpoint: {str(post_err)}")
    else:
        logger.error("Skipped posting to Slack because SLACK_WEBHOOK_URL is missing!")

    return {
        'statusCode': 200,
        'body': json.dumps('Proactive response pipeline execution completed successfully.')
    }