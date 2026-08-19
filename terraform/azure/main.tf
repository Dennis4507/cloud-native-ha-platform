# ==============================================================================
# WHAT THIS FILE BUILDS
# ==============================================================================
# By the end of this file, Azure will have two complete, independent sets of
# infrastructure - one in West Europe, one in Germany West Central - each
# containing:
# a private network, a firewall, a load balancer with its own public address,
# and two virtual machines that will later become a Kubernetes cluster.
# Both regions are built from the same blocks of code below, not copy-pasted
# twice, so the two regions can never quietly drift apart from each other.
# Kubernetes itself is not installed by this file - that happens next, using
# Ansible, once these machines exist.

# ------------------------------------------------------------------------------
# RESOURCE GROUP: the folder that holds everything else
# ------------------------------------------------------------------------------
# This resource group already exists - it was created once, by hand, as part
# of setting up the isolated sandbox identity, before Terraform ever ran.
# Its own location is just metadata (where Azure stores the record of the
# resource group itself); it does NOT control where the resources inside it
# get created - each one below sets its own location independently. So this
# is deliberately its own fixed value, matching where it actually already
# is, rather than reusing var.location_primary - reusing that variable would
# make Terraform think the resource group's region needs to change every
# time it runs, which for a resource group means destroying and recreating
# it, not a safe in-place update.
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = "germanywestcentral"
}

# ------------------------------------------------------------------------------
# REGIONS: one list describing both West Europe and Germany West Central
# ------------------------------------------------------------------------------
# Rather than writing every resource below twice (once for each region), we
# describe both regions once, here, and then tell Terraform to build one copy
# of each resource per region automatically. This is the "for_each" pattern
# used throughout this file: wherever you see "for_each = local.regions", it
# means "do this once for West Europe, and once for the secondary region."
# The secondary key is named "germany-west", not "north-eu", because the
# secondary region actually is Germany West Central (see variables.tf for
# why North Europe was dropped) - naming every resource in it "-north-eu"
# would be actively misleading about where it really runs.
locals {
  regions = {
    "west-eu" = {
      location               = var.location_primary
      vnet_address_space     = var.vnet_address_space_primary
      subnet_address_prefix  = var.subnet_address_prefix_primary
    }
    "germany-west" = {
      location               = var.location_secondary
      vnet_address_space     = var.vnet_address_space_secondary
      subnet_address_prefix  = var.subnet_address_prefix_secondary
    }
  }
}

# ------------------------------------------------------------------------------
# FIREWALL: built before any machine exists, so nothing is ever left exposed
# ------------------------------------------------------------------------------
# Azure calls this a "Network Security Group", or NSG - it is a firewall that
# controls which traffic is allowed to reach our virtual machines. By default
# every port is closed. We open exactly three: SSH (port 22, so we can
# configure the machines), the Kubernetes API (port 6443, so the "kubectl"
# command can manage the cluster), and regular web traffic (port 80, because
# the whole point of this project is a website other people can visit).
# The first two are locked to Denis's own IP address only. The third is open
# to everyone. Everything else stays blocked automatically, using a rule
# Azure already includes by default in every NSG - we do not need to write
# that part ourselves.
resource "azurerm_network_security_group" "this" {
  for_each = local.regions

  name                = "nsg-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowSSHFromAdmin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowK3sAPIFromAdmin"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = var.admin_source_ip
    destination_address_prefix = "*"
  }

  # Discovered live, while joining the first agent node: the K3s API port
  # (6443) also needs to be reachable from the OTHER machine in this same
  # region, not just from Denis's own IP - that's how an agent actually
  # joins its server. "VirtualNetwork" is a built-in Azure label meaning
  # "any address inside this network's own private range" - it scopes the
  # rule to this region's machines talking to each other over their
  # private addresses, not the whole internet.
  #
  # One thing worth being precise about, since it cost real time to work
  # out: this rule only matches traffic that actually uses private VNet
  # addressing. The agent originally tried joining via the server's PUBLIC
  # IP - and even though both machines are in the same virtual network,
  # Azure treats a public-IP-to-public-IP connection as ordinary internet
  # traffic, not "VirtualNetwork" traffic, so this rule silently never
  # matched it. The real fix was on the Ansible side: pointing the agent at
  # the server's private address instead, which is both what this rule
  # correctly allows and the right architecture anyway - internal cluster
  # traffic has no reason to round-trip through public IPs at all.
  security_rule {
    name                       = "AllowK3sAPIWithinVNet"
    priority                   = 115
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPFromAnywhere"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Added alongside the Hello World ingress work: port 80 alone was only
  # ever enough for the plain HTTP demo. Requirement 4 asks for HTTPS -
  # encrypted traffic, terminated by the ingress controller - which travels
  # over port 443, a completely separate port from 80, not an upgraded
  # version of it. Without this rule, the certificate and ingress
  # configuration could be perfect and a browser would still never be able
  # to reach it, because the firewall would drop the connection before it
  # ever got there.
  security_rule {
    name                       = "AllowHTTPSFromAnywhere"
    priority                   = 125
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ------------------------------------------------------------------------------
# NETWORK: a private, isolated network for each region
# ------------------------------------------------------------------------------
# A "virtual network" (VNet) is Azure's version of a private office network -
# the machines inside it can talk to each other, and it is separate from
# every other customer's network on Azure. Inside each VNet we carve out one
# smaller range of addresses, called a subnet, which is where our virtual
# machines will actually be placed. Immediately after creating the subnet,
# we attach the firewall we just built to it, so the two are connected from
# the very first moment the subnet exists.
resource "azurerm_virtual_network" "this" {
  for_each = local.regions

  name                = "vnet-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [each.value.vnet_address_space]
}

resource "azurerm_subnet" "vmss" {
  for_each = local.regions

  name                 = "subnet-${each.key}-vmss"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.this[each.key].name
  address_prefixes     = [each.value.subnet_address_prefix]
}

resource "azurerm_subnet_network_security_group_association" "vmss" {
  for_each = local.regions

  subnet_id                 = azurerm_subnet.vmss[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# ------------------------------------------------------------------------------
# IDENTITY: how our virtual machines prove who they are to other Azure services
# ------------------------------------------------------------------------------
# Instead of storing a password on every virtual machine so it can access
# things like storage accounts later in the project, Azure lets us create an
# "identity" - think of it like an employee badge. Any machine holding this
# badge can be granted access to other services without ever having a
# password written down anywhere. We create one badge and share it between
# both regions' machines, rather than a separate badge per machine, because
# this badge exists independently - it is not deleted if a virtual machine
# is rebuilt, which happens often while we are testing. Any permission we
# grant to this badge later stays in place even through that kind of rebuild.
resource "azurerm_user_assigned_identity" "main" {
  name                = "id-ha-platform"
  location            = var.location_primary
  resource_group_name = azurerm_resource_group.main.name
}

# ------------------------------------------------------------------------------
# LOAD BALANCER: one stable address and a health check, per region
# ------------------------------------------------------------------------------
# Each region gets its own load balancer, sitting in front of its two virtual
# machines. It does two jobs: it gives the whole region one fixed public IP
# address to be reached at, and it checks every 5 seconds whether each
# machine behind it is actually responding on port 80. That health check
# matters beyond just this load balancer - it is also what lets Azure notice
# a broken machine and replace it automatically later in this file.
#
# It is worth being clear about what this load balancer is NOT for: it does
# not decide whether to send traffic to West Europe or Germany West Central -
# that decision needs something that can see both regions at once, which this
# load balancer cannot, since it only knows about the one region it lives
# in. That cross-region decision is a separate piece we build later.
resource "azurerm_public_ip" "lb" {
  for_each = local.regions

  name                = "pip-lb-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "this" {
  for_each = local.regions

  name                = "lb-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.lb[each.key].id
  }
}

resource "azurerm_lb_backend_address_pool" "this" {
  for_each = local.regions

  loadbalancer_id = azurerm_lb.this[each.key].id
  name            = "backend-${each.key}"
}

resource "azurerm_lb_probe" "http" {
  for_each = local.regions

  loadbalancer_id     = azurerm_lb.this[each.key].id
  name                = "probe-http"
  protocol            = "Tcp"
  port                = 80
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http" {
  for_each = local.regions

  loadbalancer_id                = azurerm_lb.this[each.key].id
  name                           = "rule-http"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this[each.key].id]
  probe_id                       = azurerm_lb_probe.http[each.key].id
}

# The load balancer only ever forwarded port 80 - fine for the plain HTTP
# demo, but Requirement 4's HTTPS traffic arrives on port 443, a genuinely
# different port the load balancer was never told to pass through at all.
# Re-using the same health probe (still just a plain TCP check on port 80)
# is deliberate, not a shortcut: it's still checking "is a working web
# server actually listening on this machine," which is exactly as true for
# the 443 rule as it is for the 80 one - a separate probe on 443 wouldn't
# learn anything different, since Traefik only starts listening on 443 once
# NGINX itself is healthy.
resource "azurerm_lb_rule" "https" {
  for_each = local.regions

  loadbalancer_id                = azurerm_lb.this[each.key].id
  name                           = "rule-https"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this[each.key].id]
  probe_id                       = azurerm_lb_probe.http[each.key].id
}

# ------------------------------------------------------------------------------
# VIRTUAL MACHINES: the actual servers our Kubernetes cluster will run on
# ------------------------------------------------------------------------------
# This is the core of the whole project: a "Virtual Machine Scale Set"
# (VMSS), which is Azure's way of managing a group of identical virtual
# machines as one unit. Each region gets its own scale set of 2 machines -
# 2 is the minimum needed for our later Kubernetes setup to demonstrate that
# an application keeps running even if one machine goes down.
#
# A few specific choices worth explaining:
#
# - Login is by SSH key only, never a password. Combined with the firewall
#   above, which already blocks SSH from everyone except Denis's own IP,
#   this means there is no password anywhere that could be guessed or
#   leaked.
#
# - The operating system disk is a normal, network-attached managed disk,
#   not the faster "ephemeral" kind that stores it on the machine's own
#   local storage. Ephemeral was tried first, since it boots faster at no
#   extra cost - but Standard_B2s's local storage is only 8 GB, and the
#   Ubuntu image needs more room than that, so Azure rejected it outright
#   ("OS disk of Ephemeral VM with size greater than 8 GB is not allowed").
#   A normal managed disk has a small cost (a few cents) and a slightly
#   slower boot, but works reliably on this VM size.
#
# - "Accelerated networking", a feature that speeds up network traffic, is
#   left turned off - not because this VM size can't support it (it can),
#   but because this project has no actual need for that extra network
#   throughput, and turning on a feature with no real benefit just adds one
#   more thing that could go wrong for no reason.
#
# - "automatic_instance_repair" connects the health check from the load
#   balancer above directly to this scale set: if a machine stops
#   responding on port 80 for more than the grace period, Azure replaces it
#   on its own, without anyone needing to notice or step in. It's disabled
#   for now, though - turned off, not just given a longer grace period.
#   The reason: nothing is listening on port 80 yet (no app has been
#   deployed), so every instance fails that health check from the moment it
#   boots. Discovered live, during Ansible setup: one instance was silently
#   replaced mid-session, with a new public IP that no longer matched the
#   inventory - genuine proof the feature works, but actively disruptive
#   while there's nothing real for the check to measure. Re-enable this
#   once the Hello World app is actually deployed and something is really
#   listening on port 80.
resource "azurerm_linux_virtual_machine_scale_set" "this" {
  for_each = local.regions

  name                = "vmss-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.vm_size
  instances           = 2

  admin_username                  = var.admin_username
  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching               = "ReadWrite"
  }

  network_interface {
    name                           = "nic-${each.key}"
    primary                        = true
    enable_accelerated_networking  = false

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.vmss[each.key].id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.this[each.key].id]

      # Gives every individual instance its own public IP, generated and
      # managed automatically as part of the scale set itself - not four
      # separate, manually-tracked Public IP resources. This is what lets
      # Ansible reach each machine directly over SSH to install Kubernetes.
      #
      # IMPORTANT: this is an administrative access path only. It has
      # nothing to do with this platform's actual high-availability design.
      # If Azure replaces a broken instance automatically, the replacement
      # gets a brand-new public IP - the old one is gone regardless of any
      # setting here. The address real users (or the failover proxy) ever
      # talk to is the load balancer's frontend IP, set up back in Phase 1,
      # which never changes no matter what happens to the instances behind
      # it. That separation is deliberate: application availability never
      # depends on any single machine's address, only administrative SSH
      # access does.
      public_ip_address {
        name = "pip-instance-${each.key}"
      }
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }

  health_probe_id = azurerm_lb_probe.http[each.key].id
  automatic_instance_repair {
    enabled      = false
    grace_period = "PT30M"
  }

  # "Manual" means these machines only change when we deliberately run
  # "terraform apply" again, or when automatic_instance_repair above steps
  # in for a genuinely broken machine - never on a schedule Azure decides
  # for itself. That predictability matters more here than automatic
  # patching does, given this cluster needs to be in a known, stable state
  # right before a live presentation.
  upgrade_mode = "Manual"
}
