import json
import logging
import os
import time
import boto3
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(
    level=getattr(logging, log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configure boto3 logging if needed for debugging
if log_level == 'DEBUG':
    boto3.set_stream_logger('boto3', logging.DEBUG)
    boto3.set_stream_logger('botocore', logging.DEBUG)

# Initialize AWS clients
ec2_client = boto3.client('ec2')
cloudwatch_client = boto3.client('cloudwatch')

# Configuration
CPU_THRESHOLD = 1.0  # CPU utilization percentage threshold
IDLE_DURATION_HOURS = 3  # Hours of idle time before shutdown
DRY_RUN = os.environ.get('DRY_RUN', 'false').lower() == 'true'
ENABLE_DETAILED_MONITORING = os.environ.get('ENABLE_DETAILED_MONITORING', 'false').lower() == 'true'

# Instance types to exclude (P and G types for GPU/ML workloads)
EXCLUDED_INSTANCE_TYPES = ['p', 'g']


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for EC2 auto-shutdown
    """
    logger.info("Starting EC2 auto-shutdown process")
    
    try:
        # Get all running EC2 instances
        instances = get_running_instances()
        logger.info(f"Found {len(instances)} running instances")
        
        shutdown_candidates = []
        skipped_instances = []
        
        for instance in instances:
            instance_id = instance['InstanceId']
            instance_type = instance['InstanceType']
            
            # Check if instance should be evaluated for shutdown
            skip_reason = should_skip_instance(instance)
            if skip_reason:
                skipped_instances.append({
                    'instance_id': instance_id,
                    'instance_type': instance_type,
                    'reason': skip_reason
                })
                logger.info(f"Skipping {instance_id} ({instance_type}): {skip_reason}")
                continue
            
            # Enable detailed monitoring if needed and configured
            monitoring_enabled = enable_detailed_monitoring_if_needed(instance_id)
            if monitoring_enabled:
                logger.info(f"Enabled detailed monitoring for {instance_id}, waiting 60 seconds for metrics")
                time.sleep(60)  # Wait for new metrics to be available
            
            # Check CPU utilization
            if is_instance_idle(instance_id):
                shutdown_candidates.append(instance)
                logger.info(f"Instance {instance_id} ({instance_type}) is idle and will be shut down")
            else:
                logger.info(f"Instance {instance_id} ({instance_type}) is active, keeping running")
        
        # Perform shutdowns
        shutdown_results = []
        if shutdown_candidates:
            for instance in shutdown_candidates:
                result = shutdown_instance(instance)
                shutdown_results.append(result)
        
        # Prepare response
        response = {
            'statusCode': 200,
            'body': {
                'message': 'EC2 auto-shutdown completed successfully',
                'total_instances_evaluated': len(instances),
                'instances_skipped': len(skipped_instances),
                'instances_shutdown': len(shutdown_results),
                'dry_run': DRY_RUN,
                'skipped_instances': skipped_instances,
                'shutdown_results': shutdown_results
            }
        }
        
        logger.info(f"Process completed: {len(shutdown_results)} instances shut down, {len(skipped_instances)} skipped")
        return response
        
    except Exception as e:
        logger.error(f"Error in EC2 auto-shutdown: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': {
                'error': str(e),
                'message': 'EC2 auto-shutdown failed'
            }
        }


def get_running_instances() -> List[Dict[str, Any]]:
    """
    Get all running EC2 instances
    """
    try:
        response = ec2_client.describe_instances(
            Filters=[
                {
                    'Name': 'instance-state-name',
                    'Values': ['running']
                }
            ]
        )
        
        instances = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instances.append(instance)
        
        return instances
        
    except Exception as e:
        logger.error(f"Error getting running instances: {str(e)}")
        raise


def should_skip_instance(instance: Dict[str, Any]) -> Optional[str]:
    """
    Check if an instance should be skipped for shutdown
    Returns skip reason or None if instance should be evaluated
    """
    instance_type = instance['InstanceType']
    instance_id = instance['InstanceId']
    
    # Check if instance type is excluded (P or G types)
    for excluded_type in EXCLUDED_INSTANCE_TYPES:
        if instance_type.lower().startswith(excluded_type):
            return f"Instance type {instance_type} is excluded (P/G type)"
    
    # Check shutdown tag
    tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
    shutdown_tag = tags.get('Shutdown', '').lower()
    
    if shutdown_tag == 'no':
        return "Instance has 'Shutdown=No' tag"
    
    return None


def enable_detailed_monitoring_if_needed(instance_id: str) -> bool:
    """
    Enable detailed monitoring for an instance if it's not already enabled
    Returns True if monitoring was enabled, False if already enabled or failed
    """
    if not ENABLE_DETAILED_MONITORING:
        return False
    
    try:
        # Check current monitoring status
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                monitoring_state = instance.get('Monitoring', {}).get('State', 'disabled')
                
                if monitoring_state == 'disabled':
                    logger.info(f"Enabling detailed monitoring for instance {instance_id}")
                    
                    if not DRY_RUN:
                        # Enable detailed monitoring
                        monitor_response = ec2_client.monitor_instances(InstanceIds=[instance_id])
                        
                        # Log the result
                        for monitor_info in monitor_response.get('InstanceMonitorings', []):
                            new_state = monitor_info.get('Monitoring', {}).get('State', 'unknown')
                            logger.info(f"Instance {instance_id} monitoring state changed to: {new_state}")
                        
                        return True
                    else:
                        logger.info(f"DRY_RUN: Would enable detailed monitoring for {instance_id}")
                        return True
                        
                elif monitoring_state == 'enabled':
                    logger.debug(f"Instance {instance_id} already has detailed monitoring enabled")
                    return False
                    
                elif monitoring_state == 'pending':
                    logger.info(f"Instance {instance_id} monitoring state is pending")
                    return False
                    
    except Exception as e:
        logger.error(f"Error enabling detailed monitoring for instance {instance_id}: {str(e)}")
        return False
    
    return False


def is_instance_idle(instance_id: str) -> bool:
    """
    Check if an instance has been idle (low CPU) for the specified duration
    Takes into account instance launch time to ensure we have sufficient data
    """
    try:
        # Get instance launch time
        instance_response = ec2_client.describe_instances(InstanceIds=[instance_id])
        launch_time = None
        
        for reservation in instance_response['Reservations']:
            for instance in reservation['Instances']:
                launch_time = instance.get('LaunchTime')
                break
        
        if not launch_time:
            logger.warning(f"Could not get launch time for instance {instance_id}")
            return False
        
        # Calculate time since launch
        current_time = datetime.utcnow().replace(tzinfo=launch_time.tzinfo)
        time_since_launch = current_time - launch_time
        
        # Check if instance has been running long enough for reliable metrics
        required_runtime_hours = IDLE_DURATION_HOURS + 0.5  # Add 30 minutes buffer
        if time_since_launch < timedelta(hours=required_runtime_hours):
            logger.info(f"Instance {instance_id} launched {time_since_launch} ago, need at least {required_runtime_hours} hours for evaluation")
            return False
        
        # Calculate metric collection period
        end_time = datetime.utcnow()
        standard_start_time = end_time - timedelta(hours=IDLE_DURATION_HOURS)
        
        # Only consider launch time if instance was launched within the last 3 hours
        launch_time_utc = launch_time.replace(tzinfo=None)
        if launch_time_utc > standard_start_time:
            # Instance launched within last 3 hours - use launch time as start
            metrics_start_time = launch_time_utc
        else:
            # Instance launched more than 3 hours ago - use standard 3-hour lookback
            metrics_start_time = standard_start_time
        
        response = cloudwatch_client.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='CPUUtilization',
            Dimensions=[
                {
                    'Name': 'InstanceId',
                    'Value': instance_id
                }
            ],
            StartTime=metrics_start_time,
            EndTime=end_time,
            Period=300,  # 5-minute periods
            Statistics=['Average']
        )
        
        datapoints = response.get('Datapoints', [])
        
        if not datapoints:
            logger.warning(f"No CPU metrics found for instance {instance_id}")
            return False
        
        # Sort datapoints by timestamp
        datapoints.sort(key=lambda x: x['Timestamp'])
        
        # Calculate expected number of datapoints for 3 hours (36 * 5-minute periods)
        expected_datapoints = int(IDLE_DURATION_HOURS * 12)  # 12 datapoints per hour
        
        # Check if we have sufficient datapoints (at least 90% of expected)
        min_required_datapoints = int(expected_datapoints * 0.9)
        if len(datapoints) < min_required_datapoints:
            logger.info(f"Insufficient metrics for instance {instance_id}: {len(datapoints)} datapoints, need at least {min_required_datapoints}")
            return False
        
        # Check for gaps in 5-minute intervals - ensure continuous monitoring
        time_gaps = []
        for i in range(1, len(datapoints)):
            time_diff = (datapoints[i]['Timestamp'] - datapoints[i-1]['Timestamp']).total_seconds()
            if time_diff > 360:  # More than 6 minutes gap (allowing for slight CloudWatch delays)
                time_gaps.append(time_diff)
        
        if time_gaps:
            total_gap_time = sum(time_gaps)
            max_allowed_gap = 600  # 10 minutes total gap allowed
            if total_gap_time > max_allowed_gap:
                logger.info(f"Instance {instance_id} has significant gaps in metrics ({total_gap_time}s total), skipping evaluation")
                return False
        
        # Use the most recent datapoints for idle evaluation
        recent_datapoints = datapoints[-expected_datapoints:] if len(datapoints) >= expected_datapoints else datapoints
        
        idle_count = sum(1 for dp in recent_datapoints if dp['Average'] <= CPU_THRESHOLD)
        idle_percentage = (idle_count / len(recent_datapoints)) * 100
        
        logger.info(f"Instance {instance_id}: {idle_percentage:.1f}% of {len(recent_datapoints)} datapoints below {CPU_THRESHOLD}% CPU (launched {time_since_launch} ago)")
        
        # Consider idle only if ALL datapoints are below threshold (100%)
        return idle_percentage == 100
        
    except Exception as e:
        logger.error(f"Error checking CPU metrics for instance {instance_id}: {str(e)}")
        return False


def shutdown_instance(instance: Dict[str, Any]) -> Dict[str, Any]:
    """
    Shutdown an EC2 instance
    """
    instance_id = instance['InstanceId']
    instance_type = instance['InstanceType']
    
    try:
        if DRY_RUN:
            logger.info(f"DRY RUN: Would shutdown instance {instance_id} ({instance_type})")
            return {
                'instance_id': instance_id,
                'instance_type': instance_type,
                'action': 'dry_run',
                'status': 'success',
                'message': 'Would be shut down (dry run mode)'
            }
        else:
            # Get instance name for better logging
            tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
            instance_name = tags.get('Name', 'Unnamed')
            
            # Stop the instance
            response = ec2_client.stop_instances(InstanceIds=[instance_id])
            
            logger.info(f"Successfully initiated shutdown for instance {instance_id} ({instance_name}, {instance_type})")
            
            return {
                'instance_id': instance_id,
                'instance_type': instance_type,
                'instance_name': instance_name,
                'action': 'shutdown',
                'status': 'success',
                'message': 'Shutdown initiated successfully'
            }
            
    except Exception as e:
        error_msg = f"Failed to shutdown instance {instance_id}: {str(e)}"
        logger.error(error_msg)
        
        return {
            'instance_id': instance_id,
            'instance_type': instance_type,
            'action': 'shutdown',
            'status': 'error',
            'message': error_msg
        }