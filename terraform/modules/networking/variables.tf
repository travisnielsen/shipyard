variable "prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "vnet_cidr" {
  type = string
}

variable "subnet_cidrs" {
  type = object({
    infra              = string
    aks_nodes          = string
    container_apps_env = string
    private_endpoints  = string
    vdi_integration    = string
  })
}

variable "tags" {
  type = map(string)
}
