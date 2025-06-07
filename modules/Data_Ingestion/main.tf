provider "aws" {
  region                      = var.region
}

# Create an S3 bucket
resource "aws_s3_bucket" "my_bucket" {
  bucket = var.bucket_name

  tags = {
    Name        = "MyIntakeBucket"
    Environment = "Dev"
  }
  lifecycle {
    prevent_destroy = false  # Prevent S3 bucket deletion
    ignore_changes  = [tags]  # Ignore tag changes
  }
}

# Block public access to the bucket
resource "aws_s3_bucket_public_access_block" "my_bucket_public_access" {
  bucket = aws_s3_bucket.my_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# S3 Bucket Notification to trigger Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.my_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.csv_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# sns resource
resource "aws_sns_topic" "error_notifications" {
  name = "csv-pipeline-errors"
}

# DynamoDB Table for customer records
resource "aws_dynamodb_table" "customer_records" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "tenant_id"
  range_key      = "medical_record_number"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  attribute {
    name = "medical_record_number"
    type = "S"
  }

  tags = {
    Name        = "CustomerRecords"
    Environment = "Dev"
  }
}

# DynamoDB Table for tracking processed files
resource "aws_dynamodb_table" "processed_files" {
  name           = var.processed_files_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "file_hash"

  attribute {
    name = "file_hash"
    type = "S"
  }

  tags = {
    Name        = "ProcessedFiles"
    Environment = "Dev"
  }
}

# # IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "csv_processor_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "csv_processor_lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = [
          aws_s3_bucket.my_bucket.arn,
          "${aws_s3_bucket.my_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = aws_sns_topic.error_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.customer_records.arn,
          aws_dynamodb_table.processed_files.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "csv_processor" {
  filename         = "lambda/lambda_function_v0.0.19.zip"
  function_name    = "csv_processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      DYNAMODB_TABLE      = var.dynamodb_table_name
      FILE_TRACKER_TABLE  = var.processed_files_table_name
      SNS_TOPIC_ARN       = aws_sns_topic.error_notifications.arn
      S3_BUCKET           = var.bucket_name
    }
  }

  layers = [
    "arn:aws:lambda:us-east-1:213396388376:layer:Combined_Layer:6",
  ]

  depends_on = [aws_iam_role_policy.lambda_policy]
}

# Lambda Permission for S3
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.csv_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.my_bucket.arn
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/csv_processor"
  retention_in_days = 14
}