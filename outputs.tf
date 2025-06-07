output "created_bucket" {
  value = module.Data_Ingestion.s3_bucket_name
}
output "created_dynamodb_table_name" {
  value = module.Data_Ingestion.dynamodb_table_name
}

output "processed_files_table_name" {
  value = module.Data_Ingestion.processed_files_table_name
}

output "lambda_function_name" {
  value = module.Data_Ingestion.lambda_function_name
}

output "lambda_role_arn" {
  value = module.Data_Ingestion.lambda_roles
}
output "sns_error_notification_arn" {
  value = module.Data_Ingestion.SNS_ERROR_NOTIFICATIONS
}
