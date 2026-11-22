## S3 Bucket provisioning for keeping the backups

resource "aws_s3_bucket" "backup" {
  bucket_prefix = "${var.cluster_name}-mysql-backup-"

  # will allows terraform destroy even when backups exist
  force_destroy = true
}

# Version history is being kept
resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption of objects at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# The bucket must never be public
resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Delete backups after the retention period gets over
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.retention_days
    }
  }
}

# ---------------------------------------------------------------------------
# IAM role for the backup/restore pods (EKS Pod Identity)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "backup" {
  name_prefix = "${var.cluster_name}-mysql-backup-"

  # Only the EKS Pod Identity service may assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# Least privilege: read/write objects and list this one bucket only
resource "aws_iam_role_policy" "backup" {
  name = "mysql-backup-s3"
  role = aws_iam_role.backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadWriteBackups"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.backup.arn}/*"
      },
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.backup.arn
      }
    ]
  })
}

# Bind the Kubernetes service account to the IAM role
resource "aws_eks_pod_identity_association" "backup" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.backup.arn
}