import boto3
import json
import os

def handler(event, context):
    ec2 = boto3.client(
        'ec2',
        endpoint_url='http://172.17.0.1:4566',
        region_name='us-east-1',
        aws_access_key_id='test',
        aws_secret_access_key='test'
    )
    
    action = event.get('action', 'status')
    instance_id = event.get('instance_id', os.environ.get('INSTANCE_ID', ''))
    
    if action == 'start':
        ec2.start_instances(InstanceIds=[instance_id])
        return {'statusCode': 200, 'body': json.dumps({'message': f'Instance {instance_id} demarree'})}
    elif action == 'stop':
        ec2.stop_instances(InstanceIds=[instance_id])
        return {'statusCode': 200, 'body': json.dumps({'message': f'Instance {instance_id} stoppee'})}
    else:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        state = response['Reservations'][0]['Instances'][0]['State']['Name']
        return {'statusCode': 200, 'body': json.dumps({'instance_id': instance_id, 'state': state})}
