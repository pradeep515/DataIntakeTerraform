# Outputs
output "s3_bucket_name" {
  value = aws_s3_bucket.my_bucket.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.customer_records.name
}

output "processed_files_table_name" {
  value = aws_dynamodb_table.processed_files.name
}

output "lambda_function_name" {
  value = aws_lambda_function.csv_processor.function_name
}

output "lambda_roles" {
  value = aws_iam_role.lambda_role.arn
}
output "SNS_ERROR_NOTIFICATIONS" {
  value = aws_sns_topic.error_notifications.arn
}