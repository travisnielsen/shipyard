variable "prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "node_count" {
  type = number
}

variable "vm_size" {
  type = string
}

variable "acr_id" {
  type = string
}

variable "tags" {
  type = map(string)
}
