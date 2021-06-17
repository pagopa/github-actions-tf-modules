locals {
  consumers = { for hc in flatten([for h in var.eventhubs :
    [for c in h.consumers : {
      hub  = h.name
      name = c
  }]]) : format("%s.%s", hc.hub, hc.name) => hc }

  keys = { for hk in flatten([for h in var.eventhubs :
    [for k in h.keys : {
      hub = h.name
      key = k
  }]]) : format("%s.%s", hk.hub, hk.key.name) => hk }

  hubs = { for h in var.eventhubs : h.name => h }
}

resource "azurerm_eventhub_namespace" "this" {
  name                     = var.name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  sku                      = var.sku
  capacity                 = var.capacity
  auto_inflate_enabled     = var.auto_inflate_enabled
  maximum_throughput_units = var.auto_inflate_enabled ? var.maximum_throughput_units : null
  zone_redundant           = var.zone_redundant

  dynamic "network_rulesets" {
    for_each = var.network_rulesets
    content {
      default_action = network_rulesets.value["default_action"]
      # virtual_network_rule {} # optional one ore more
      dynamic "virtual_network_rule" {
        for_each = network_rulesets.value["virtual_network_rule"]
        content {
          subnet_id                                       = virtual_network_rule.value["subnet_id"]
          ignore_missing_virtual_network_service_endpoint = virtual_network_rule.value["ignore_missing_virtual_network_service_endpoint"]
        }
      }
      dynamic "ip_rule" {
        for_each = network_rulesets.value["ip_rule"]
        content {
          ip_mask = ip_rule.value["ip_mask"]
          action  = ip_rule.value["action"]
        }
      }
    }
  }

  tags = var.tags
}

resource "azurerm_eventhub" "events" {
  for_each = local.hubs

  name                = each.key
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name
  partition_count     = each.value.partitions
  message_retention   = each.value.message_retention
}

resource "azurerm_eventhub_consumer_group" "events" {
  for_each = local.consumers

  name                = each.value.name
  namespace_name      = azurerm_eventhub_namespace.this.name
  eventhub_name       = each.value.hub
  resource_group_name = var.resource_group_name
  user_metadata       = "terraform"

  depends_on = [azurerm_eventhub.events]
}

resource "azurerm_eventhub_authorization_rule" "events" {
  for_each = local.keys

  name                = each.value.key.name
  namespace_name      = azurerm_eventhub_namespace.this.name
  eventhub_name       = each.value.hub
  resource_group_name = var.resource_group_name

  listen = each.value.key.listen
  send   = each.value.key.send
  manage = each.value.key.manage

  depends_on = [azurerm_eventhub.events]
}

resource "azurerm_private_dns_zone" "eventhub" {
  count = var.sku != "Basic" ? 1 : 0

  name                = "privatelink.servicebus.windows.net"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "eventhub" {
  count = var.sku != "Basic" ? 1 : 0

  name                  = format("%s-private-dns-zone-link", var.name)
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.eventhub[0].name
  virtual_network_id    = var.virtual_network_id

  tags = var.tags
}

resource "azurerm_private_endpoint" "eventhub" {
  count = var.sku != "Basic" ? 1 : 0

  name                = format("%s-private-endpoint", var.name)
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_dns_zone_group {
    name                 = format("%s-private-dns-zone-group", var.name)
    private_dns_zone_ids = [azurerm_private_dns_zone.eventhub[0].id]
  }

  private_service_connection {
    name                           = format("%s-private-service-connection", var.name)
    private_connection_resource_id = azurerm_eventhub_namespace.this.id
    is_manual_connection           = false
    subresource_names              = ["namespace"]
  }
}

resource "azurerm_private_dns_a_record" "private_dns_a_record_eventhub" {
  count = var.sku != "Basic" ? 1 : 0

  name                = "eventhub"
  zone_name           = azurerm_private_dns_zone.eventhub[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = azurerm_private_endpoint.eventhub[0].private_service_connection.*.private_ip_address
}