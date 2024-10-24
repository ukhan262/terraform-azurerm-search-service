resource "azurerm_search_service" "srchs" {
  count                                    = var.srch_info_deploy_mode == "azurerm" ? 1 : 0
  name                                     = "srch-${var.name}"
  resource_group_name                      = var.resource_group_name
  location                                 = var.location
  sku                                      = var.sku
  local_authentication_enabled             = false
  public_network_access_enabled            = false
  partition_count                          = var.partition_count
  replica_count                            = var.replica_count
  customer_managed_key_enforcement_enabled = true
  tags                                     = var.tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_search_service" "dasd" {
  count                                    = var.srch_info_deploy_mode == "azurerm" ? 1 : 0
  name                                     = "srch-${var.name}"
  resource_group_name                      = var.resource_group_name
  location                                 = var.location
  sku                                      = var.sku
  local_authentication_enabled             = false
  public_network_access_enabled            = false
  partition_count                          = var.partition_count
  replica_count                            = var.replica_count
  customer_managed_key_enforcement_enabled = true
  tags                                     = var.tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  identity {
    type = "SystemAssigned"
  }
}
 
resource "azapi_resource" "api_srch" {
  count                     = var.srch_info_deploy_mode == "api" ? 1 : 0
  schema_validation_enabled = false
  type                      = "Microsoft.Search/searchServices@2022-09-01"
  name                      = "srch-${var.name}"
  location                  = var.location
  parent_id                 = var.resource_group_id
  identity {
    type = "SystemAssigned"
  }
  body = jsonencode({
    properties = {
      # authOptions can't be set if localauth is disabled
      # authOptions = {
      #   aadOrApiKey = {
      #     aadAuthFailureMode = "http403"
      #   }
      # }
      disableLocalAuth = var.disable_local_auth
      encryptionWithCmk = {
        enforcement                = "Enabled"
        encryptionComplianceStatus = "Compliant" #forces AzAPI use per MS
      }
      hostingMode         = "default"
      partitionCount      = tonumber(var.partition_count)
      publicNetworkAccess = "Disabled"
      replicaCount        = tonumber(var.replica_count)
    }
    sku = {
      name = var.sku
    }
    tags = var.tags
  })
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_endpoint" "ai-srch-pe" {
  name                = "pe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  # private_dns_zone_group {
  #   name                 = "privatelink.search.windows.net"
  #   private_dns_zone_ids = [var.private_dns_zone_id]
  # }
  private_service_connection {
    name                           = "peconn-${var.name}"
    is_manual_connection           = false
    subresource_names              = ["searchService"]
    private_connection_resource_id = azurerm_search_service.srchs[0].id
  }
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_search_shared_private_link_service" "search_spls" {
  for_each           = { for spl in var.spls : spl.name => spl }
  name               = each.value.name
  search_service_id  = var.srch_info_deploy_mode == "azurerm" ? azurerm_search_service.srchs[0].id : azapi_resource.api_srch[0].id
  subresource_name   = each.value.subresource_name
  target_resource_id = each.value.target_resource_id
  request_message    = each.value.request_message
}

data "azapi_resource_list" "resource" {
  depends_on = [ azurerm_search_shared_private_link_service.search_spls ]
  for_each               = { for spl in var.spls : spl.name => spl } # Loop over each resource
  type                   = each.value.taget_resource_type
  parent_id              = each.value.target_resource_id
  response_export_values = ["*"]
}

locals {
  private_endpoint_connections = [
    for resource in data.azapi_resource_list.resource : {
      name      = resource.id
      connection_names = [for connection in resource.output.value : connection.name]
    }
  ]

  # Map spls to their corresponding private endpoint connections by matching names or IDs
  mapped_resources_list = [
    for spl in var.spls : {
      name          = spl.name
      resource_type = spl.taget_resource_type
      resource_id   = spl.target_resource_id
      pe_connection = lookup(
        { for conn in local.private_endpoint_connections : conn.name => conn.connection_names },
        spl.target_resource_id,
        ""
      )
    }
  ]

  # Convert mapped_resources_list (a list) to a map where the key is the name
  mapped_resources_map = { for resource in local.mapped_resources_list : resource.name => resource }

  # Create a static set of keys for for_each
  static_keys = [for spl in var.spls : spl.name]
}

resource "azapi_update_resource" "approval" {
  for_each  = { for spl in local.static_keys : spl => lookup(local.mapped_resources_map, spl, null) }
  
  type      = each.value != null ? each.value.resource_type : null
  name      = each.value != null ? each.value.pe_connection : null
  parent_id = each.value != null ? each.value.resource_id : null

  body = jsonencode({
    properties = {
      privateLinkServiceConnectionState = {
        status = "Approved"
      }
    }
  })

  depends_on = [azurerm_search_shared_private_link_service.search_spls]
}
