output "bucket_name" {
  description = "Name of the S3 bucket that hold MySQL backups"
  value       = aws_s3_bucket.backup.bucket
}

output "role_arn" {
  description = "IAM role assumed by the backup/restore pods"
  value       = aws_iam_role.backup.arn
}
