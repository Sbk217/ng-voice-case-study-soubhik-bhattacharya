variable "cluster_name" { type = string }
variable "vpc_id" { type = string }
variable "private_route_table_ids" { type = list(string) }
variable "device_index" {
  type    = number
  default = 2 # Normally VPC CNI keeps a warm ENI at index 1 already we need to check which index is free first.
}