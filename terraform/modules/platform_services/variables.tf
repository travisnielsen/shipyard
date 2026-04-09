variable "prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "private_endpoints_subnet" {
  type = string
}

variable "acr_private_dns_zone_id" {
  type = string
}

variable "kv_private_dns_zone_id" {
  type = string
}

variable "tags" {
  type = map(string)
}
