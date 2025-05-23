variable "region" {
  description = "AWS region"
  default     = "us-east-1"
  type        = string
}
variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for customer records"
  default     = "CustomerRecords"
  type        = string
}

variable "processed_files_table_name" {
  description = "Name of the DynamoDB table for tracking processed files"
  default     = "ProcessedFiles"
  type        = string
}

variable "bucket_name" {
  description = "The name of the S3 bucket"
  type        = string
  default     = "ingestion-bucket"
}
