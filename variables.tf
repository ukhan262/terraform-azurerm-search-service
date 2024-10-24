variable "srch_info_deploy_mode" {
  type = string
  validation {
    ## only allowed values are "azure" or "api"
    condition     = contains(["azurerm", "api"], var.srch_info_deploy_mode)
    error_message = "The value must be azurerm or api."
  }
}

variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku" {
  type = string
}

variable "partition_count" {
  type = string
}

variable "replica_count" {
  type = string
}

variable "tags" {
  type    = map(any)
  default = {}
}

variable "resource_group_id" {
  type    = string
  default = ""
}

variable "disable_local_auth" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type    = string
  default = ""
}

variable "spls" {
  type = list(object({
    name                = string
    subresource_name    = string
    target_resource_id  = string
    taget_resource_type = string
    request_message     = string
  }))
}