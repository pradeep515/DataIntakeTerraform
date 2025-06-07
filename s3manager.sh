#!/bin/bash

# Simple script to run AWS CLI S3 commands based on a flag

if [ "$1" == "upload" ]; then
    # Usage: ./aws_s3_tool.sh upload local_file s3://bucket/key
    name=test_valid.csv
elif [ "$1" == "upload_invalid" ]; then
    name=test_invalid.csv
elif [ "$1" == "upload_failure" ]; then
    name=test_failure.csv

else
    echo "Usage:"
    echo "  $0 upload"
    echo "  $0 upload_invalid"
    echo "  $0 upload_failure"
    exit 1
fi

aws s3 cp /Users/pradeep/Documents/Tendo/TestProject/DataIntake_Query_Terraform/test_files/${name} s3://ingestion-bucket-24cd310b/uploads/
