import json
import boto3
import pandas as pd
import hashlib
import logging
import os
from datetime import datetime
import pytz
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
sns_client = boto3.client("sns")

def get_file_hash(bucket, key):
    logger.info(f"Attempting to get hash for bucket: {bucket}, key: {key}")
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        file_content = response["Body"].read()
        file_hash = hashlib.md5(file_content).hexdigest()
        logger.info(f"Calculated hash: {file_hash}")
        return file_hash
    except ClientError as e:
        logger.error(f"Error reading S3 file {key}: {str(e)}")
        raise

def check_duplicate_file(table, file_hash):
    """Check if file has been processed."""
    logger.info(f"Checking duplicate for table: {table.name}, hash: {file_hash}")
    try:
        response = table.get_item(Key={"file_hash": file_hash})
        logger.info(f"DynamoDB response: {response}")
        return "Item" in response
    except ClientError as e:
        logger.error(f"Error checking duplicate for hash {file_hash}: {str(e)}")
        return False

def validate_csv(df, expected_columns):
    """Validate CSV structure and data."""
    logger.info(f"Validating CSV with columns: {df.columns.tolist()}")
    if not all(col in df.columns for col in expected_columns):
        raise ValueError(f"Missing columns. Found: {df.columns}, Expected: {expected_columns}")
    if df.empty:
        raise ValueError("CSV is empty")
    if "tenant_id" not in df.columns:
        logger.warning("No tenant_id, assigning default")
        df["tenant_id"] = "default_tenant"
    if df.isnull().any().any():
        logger.warning("Missing values detected, filling defaults")
        df.fillna({
            "tenant_id": "default_tenant",
            "medical_record_number": "UNKNOWN",
            "first_name": "Unknown",
            "last_name": "Unknown",
            "date_time": pd.Timestamp.now(),
            "doctors_notes": "None"
        }, inplace=True)
    return df

def transform_data(df):
    """Clean and transform data."""
    logger.info("Transforming data")
  
    df["full_name"] = (df["first_name"].str.strip() + " " + df["last_name"].str.strip()).str.title()
    df["medical_record_number"] = df["medical_record_number"].str.strip()
    df["date_time"] = pd.to_datetime(df["date_time"]).dt.tz_localize("America/New_York").dt.tz_convert("UTC").dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    df["doctors_notes"] = df["doctors_notes"].str.strip()
    df["processed_at"] = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    return df

def store_data(df, table_name):
    """Store data in DynamoDB."""
    logger.info(f"Storing data in table: {table_name}")
    table = dynamodb.Table(table_name)
    try:
        with table.batch_writer() as batch:
            for _, row in df.iterrows():
                batch.put_item(
                    Item={
                        "tenant_id": row["tenant_id"],
                        "medical_record_number": row["medical_record_number"],
                        "full_name": row["full_name"],
                        "first_name": row["first_name"],
                        "last_name": row["last_name"],
                        "date_time": row["date_time"],
                        "doctors_notes": row["doctors_notes"],
                        "processed_at": row["processed_at"]
                    }
                )
        logger.info(f"Stored {len(df)} rows in {table_name}")
    except ClientError as e:
        logger.error(f"DynamoDB error for table {table_name}: {str(e)}")
        raise

def archive_file(bucket, key, file_hash, file_tracker_table):
    """Archive file and track in DynamoDB."""
    archive_key = f"archive/{os.path.basename(key)}"
    logger.info(f"Archiving file {key} to {archive_key}")
    try:
        s3_client.copy_object(Bucket=bucket, CopySource={"Bucket": bucket, "Key": key}, Key=archive_key)
        s3_client.delete_object(Bucket=bucket, Key=key)
        file_tracker_table.put_item(
            Item={
                "file_hash": file_hash,
                "file_name": os.path.basename(key),
                "processed_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
            }
        )
        logger.info(f"Archived {key} to {archive_key}")
    except ClientError as e:
        logger.error(f"Error archiving file {key}: {str(e)}")
        raise

def quarantine_file(bucket, key, error_message, sns_topic_arn):
    """Move file to quarantine and notify."""
    quarantine_key = f"quarantine/{os.path.basename(key)}"
    logger.info(f"Quarantining file {key} to {quarantine_key}")
    try:
        s3_client.copy_object(Bucket=bucket, CopySource={"Bucket": bucket, "Key": key}, Key=quarantine_key)
        s3_client.delete_object(Bucket=bucket, Key=key)
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Message=f"Failed to process {key}: {error_message}"
        )
        logger.info(f"Quarantined {key} to {quarantine_key}")
    except ClientError as e:
        logger.error(f"Error quarantining file {key}: {str(e)}")
        raise

def lambda_handler(event, context):
    """Lambda handler for processing S3 CSV files."""
    logger.info(f"Received event: {json.dumps(event)}")
    try:
        bucket = os.environ["S3_BUCKET"]
        customers_table = os.environ["DYNAMODB_TABLE"]  # References intake-customerrecords
        file_tracker_table = dynamodb.Table(os.environ["FILE_TRACKER_TABLE"])  # References intake-processedfiles
        sns_topic_arn = os.environ["SNS_TOPIC_ARN"]
        expected_columns = ["tenant_id", "medical_record_number", "first_name", "last_name", "date_time", "doctors_notes"]
        logger.info(f"Environment variables - Bucket: {bucket}, Customers Table: {customers_table}, File Tracker Table: {file_tracker_table.name}, SNS ARN: {sns_topic_arn}")
    except KeyError as e:
        logger.error(f"Missing environment variable: {str(e)}")
        raise

    for record in event["Records"]:
        try:
            key = record["s3"]["object"]["key"]
            logger.info(f"Processing file: {key}")
        except KeyError as e:
            logger.error(f"Error parsing S3 event: {str(e)}")
            continue

        try:
            file_hash = get_file_hash(bucket, key)
            logger.info(f"File hash is {file_hash}")
            logger.info(f"Tracker table is {file_tracker_table.name}, file hash is {file_hash}")
            status = check_duplicate_file(file_tracker_table, file_hash)
            logger.info(f"Duplicate check status: {status}")
            if status:
                logger.info(f"Skipping duplicate file: {key}")
                s3_client.delete_object(Bucket=bucket, Key=key)
                continue

            # Read CSV
            logger.info("Reading CSV")
            obj = s3_client.get_object(Bucket=bucket, Key=key)
            df = pd.read_csv(obj["Body"])
            logger.info(f"CSV data: {df.to_dict()}")

            # Validate
            logger.info("Validating CSV")
            df = validate_csv(df, expected_columns)

            # Transform
            logger.info("Transforming data")
            df = transform_data(df)

            # Store
            logger.info("Storing data")
            store_data(df, customers_table)

            # Archive and track
            logger.info("Archiving file")
            archive_file(bucket, key, file_hash, file_tracker_table)

        except Exception as e:
            logger.error(f"Error processing {key}: {str(e)}")
            logger.error(f"Exception details: {type(e).__name__}, {str(e)}")
            quarantine_file(bucket, key, str(e), sns_topic_arn)
            continue

    return {
        "statusCode": 200,
        "body": json.dumps("Processing complete")
    }