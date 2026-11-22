variable "cluster_name" {
  description = "Name of the EKS cluster"
  type = string
}

variable "kubernetes_version" {
  description = "Cluster Kubernetes version, used to pick a compatible add-on version"
  type = string
}