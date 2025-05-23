import json
import boto3
import csv
import io
import logging
from botocore.exceptions import ClientError
import os
from urllib.parse import unquote_plus

# Initialize logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    customer_table = dynamodb.Table(os.environ['CUSTOMER_TABLE'])
    processed_files_table = dynamodb.Table(os.environ['PROCESSED_FILES_TABLE'])
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        try:
            # Check if file was already processed
            response = processed_files_table.get_item(Key={'file_key': key})
            if 'Item' in response:
                logger.info(f"File {key} already processed, skipping.")
                continue
                
            # Get CSV file from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            csv_content = response['Body'].read().decode('utf-8')
            csv_file = io.StringIO(csv_content)
            csv_reader = csv.DictReader(csv_file)
            
            # Validate required fields
            required_fields = {'tenant_id', 'customer_id', 'name', 'email', 'phone'}
            if not required_fields.issubset(csv_reader.fieldnames):
                logger.error(f"Missing required fields in {key}")
                continue
                
            # Process each row
            for row in csv_reader:
                try:
                    customer_table.put_item(
                        Item={
                            'tenant_id': row['tenant_id'],
                            'customer_id': row['customer_id'],
                            'name': row['name'],
                            'email': row['email'],
                            'phone': row['phone']
                        },
                        ConditionExpression='attribute_not_exists(tenant_id) AND attribute_not_exists(customer_id)'
                    )
                except ClientError as e:
                    if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
                        logger.info(f"Record for tenant {row['tenant_id']}, customer {row['customer_id']} already exists, updating.")
                        customer_table.update_item(
                            Key={
                                'tenant_id': row['tenant_id'],
                                'customer_id': row['customer_id']
                            },
                            UpdateExpression="set #n = :n, email = :e, phone = :p",
                            ExpressionAttributeNames={'#n': 'name'},
                            ExpressionAttributeValues={
                                ':n': row['name'],
                                ':e': row['email'],
                                ':p': row['phone']
                            }
                        )
                    else:
                        logger.error(f"Error processing record for tenant {row['tenant_id']}, customer {row['customer_id']}: {str(e)}")
                        continue
            
            # Mark file as processed
            processed_files_table.put_item(
                Item={
                    'file_key': key,
                    'processed_at': context.get('aws_request_id')
                }
            )
            logger.info(f"Successfully processed file: {key}")
            
        except ClientError as e:
            logger.error(f"Error processing file {key}: {str(e)}")
            continue
            
    return {
        'statusCode': 200,
        'body': json.dumps('Processing complete')
    }