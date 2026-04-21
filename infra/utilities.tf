# Utility compute for operator workflows and connectivity validation.
resource "azurerm_network_interface" "dev_vm" {
  count = var.deploy_test_vm ? 1 : 0

  name                = "nic-${var.prefix}-workload-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.networking.subnets["dev_vm"].resource_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "dev_vm" {
  count = var.deploy_test_vm ? 1 : 0

  name                = "vm-${var.prefix}"
  computer_name       = "vm-${var.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  size                = var.dev_vm_size
  admin_username      = "azureuser"
  admin_password      = var.dev_vm_admin_password
  network_interface_ids = [
    azurerm_network_interface.dev_vm[0].id
  ]

  os_disk {
    caching = "ReadWrite"
    # Keep test VM non-disruptive during drift reconciliation; Premium would force replacement.
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-25h2-pro"
    version   = "latest"
  }

  lifecycle {
    # Azure Policy may attach a system-assigned identity after creation.
    ignore_changes = [identity]
  }

  tags = var.tags
}

resource "azurerm_public_ip" "bastion" {
  count = var.deploy_test_vm ? 1 : 0

  name                = "pip-${var.prefix}-bastion"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    # Prevent forced replacement churn from Azure/provider normalization-only drift.
    ignore_changes = [
      ip_tags,
      zones,
    ]
  }
}

resource "azurerm_bastion_host" "workload" {
  count = var.deploy_test_vm ? 1 : 0

  name                = "bas-${var.prefix}-workload"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Basic"
  copy_paste_enabled  = true
  tags                = var.tags

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = module.networking.subnets["bastion"].resource_id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }


  timeouts {
    create = "45m"
    update = "45m"
  }
}