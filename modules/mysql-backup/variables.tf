variable "cluster_name" {
  description = "Name of the EKS cluster the backup pods run in"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the backup/restore pods"
  type        = string
  default     = "casestudy"
}

variable "service_account" {
  description = "Kubernetes service account used by the backup/restore pods"
  type        = string
  default     = "mysql-backup"
}

variable "retention_days" {
  description = "Number of days backups are kept before they expire"
  type        = number
  default     = 14
}
