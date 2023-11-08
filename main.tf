 terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
    subscription_id = "227bd863-5ec5-439d-a98f-214fcec266d7"
    client_id = "a83fd1b3-c420-4039-8934-f2e5f174d149"
    client_secret = "KJy8Q~5fJv3yhAoUZJdBJE~~KWJjxTtPtPjXjaFq"
    tenant_id = "c29c3861-3b3e-46a5-9820-03e87437b533"
  features {
    key_vault {
    purge_soft_delete_on_destroy    = true
    recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "current" {}

data "template_cloudinit_config" "linuxconfig" {
  gzip  = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = "packages: ['nginx']"
  }
}

# Create a resource group
resource "azurerm_resource_group" "resource_group" {
  name     = "three-tier-arch-rg"
  location = "Canada Central"
}

#Define Azure Key Vault
resource "azurerm_key_vault" "key_vault" {
  name                = "madhuterravault"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name            = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get", "Create",
    ]

    secret_permissions = [
      "Get", "Backup", "Delete", "List", "Purge", "Recover", "Restore", "Set",
    ]

    storage_permissions = [
      "Get",
    ]
  }
}

# Creating a secret in the key vault
resource "azurerm_key_vault_secret" "win_vm_password" {
  name         = "win-vm-password"
  value        = "Azurewin@123"
  key_vault_id = azurerm_key_vault.key_vault.id
  depends_on = [
    azurerm_key_vault.key_vault
  ]
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "virtual_network" {
  name                = "virtual-network-project"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet1" {
  name                 = "subnet1"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "subnet2" {
  name                 = "subnet2"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "lin_public_ip" {
  name                = "lin-publicip1"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "win_public_ip" {
  name                = "win-publicip1"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic_lin" {
  name                = "project-network-interface"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.lin_public_ip.id
  }
}

  resource "azurerm_network_interface" "nic_win" {
  name                = "win-network-interface"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.win_public_ip.id
  }
  depends_on = [ azurerm_virtual_network.virtual_network ]
}

resource "azurerm_availability_set" "availability_set" {
  name                = "project-vm-availability-set"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  platform_update_domain_count = 3
  platform_fault_domain_count = 3
}

resource "azurerm_windows_virtual_machine" "windows_vm" {
  name                  = "windows-vm"
  resource_group_name   = azurerm_resource_group.resource_group.name
  location              = azurerm_resource_group.resource_group.location
  network_interface_ids = [azurerm_network_interface.nic_win.id]
  size                  = "Standard_F2"
  admin_username        = "adminuser"
  admin_password        = azurerm_key_vault_secret.win_vm_password.value
  availability_set_id   = azurerm_availability_set.availability_set.id
  #zone               = "1"
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [
    azurerm_network_interface.nic_win, 
    azurerm_availability_set.availability_set,
    azurerm_key_vault_secret.win_vm_password
    ]
}

resource "azurerm_linux_virtual_machine" "linux_vm" {
  name                = "project-linux-machine"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  admin_password      = "Azure@123"
  availability_set_id = azurerm_availability_set.availability_set.id
  #zone               = "2"
  disable_password_authentication = false
  custom_data = data.template_cloudinit_config.linuxconfig.rendered
  network_interface_ids = [
    azurerm_network_interface.nic_lin.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  depends_on = [
    azurerm_network_interface.nic_lin,
    azurerm_availability_set.availability_set
  ]
}

resource "azurerm_managed_disk" "lin_data_disk" {
  name                 = "linuxdatadisk"
  location             = azurerm_resource_group.resource_group.location
  resource_group_name  = azurerm_resource_group.resource_group.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 16
}

resource "azurerm_managed_disk" "win_data_disk" {
  name                 = "windatadisk"
  location             = azurerm_resource_group.resource_group.location
  resource_group_name  = azurerm_resource_group.resource_group.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 16
}

# Then we need to attach the data disk to the Azure Linux Virtual machine
resource "azurerm_virtual_machine_data_disk_attachment" "lindata_disk_attach" {
  managed_disk_id    = azurerm_managed_disk.lin_data_disk.id
  virtual_machine_id = azurerm_linux_virtual_machine.linux_vm.id
  lun                = "10"
  caching            = "ReadWrite"
  depends_on = [ azurerm_linux_virtual_machine.linux_vm ]
}

# Attach the data disk to the Azure Windows Virtual machine
resource "azurerm_virtual_machine_data_disk_attachment" "windata_disk_attach" {
  managed_disk_id    = azurerm_managed_disk.win_data_disk.id
  virtual_machine_id = azurerm_windows_virtual_machine.windows_vm.id
  lun                = "10"
  caching            = "ReadWrite"
  depends_on = [ azurerm_windows_virtual_machine.windows_vm ]
}

# Azure monitor to get an email alert of the vm
resource "azurerm_monitor_action_group" "email_alert" {
  name                = "email-alert"
  resource_group_name = azurerm_resource_group.resource_group.name
  short_name          = "email"
  email_receiver {
    name          = "sendtoadmin"
    email_address = "madhumitha.srivatsa@gmail.com"
    }
  }
  resource "azurerm_monitor_metric_alert" "network_threshold_alert" {
  name                = "network_threshold_alert"
  resource_group_name = azurerm_resource_group.resource_group.name
  scopes              = [azurerm_windows_virtual_machine.windows_vm.id]
  description         = "The alert will be sent if the Network out bytes exceeds 70 bytes."

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Network Out Total"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 70
    }

  action {
    action_group_id = azurerm_monitor_action_group.email_alert.id
  }
}
  

resource "azurerm_storage_account" "storage_account" {
  name                     = "projectstorage12345"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "container" {
  name                  = "storage-container"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "blob"
}

#Uploading IIS Configuration script as a blob to the Azure Storage account
resource "azurerm_storage_blob" "blob" {
  name                   = "IIS_Config.ps1"
  storage_account_name   = azurerm_storage_account.storage_account.name
  storage_container_name = azurerm_storage_container.container.name
  type                   = "Block"
  source                 = "IIS_Config.ps1"
  depends_on = [azurerm_storage_container.container]
}

resource "azurerm_virtual_machine_extension" "linux_vm_extn" {
  name                 = "hostname"
  virtual_machine_id   = azurerm_linux_virtual_machine.linux_vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
 {
  "commandToExecute": "hostname && uptime"
 }
SETTINGS
}

resource "azurerm_virtual_machine_extension" "win_vm_extn" {
  name                 = "win-vm-extension"
  virtual_machine_id   = azurerm_windows_virtual_machine.windows_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  depends_on = [azurerm_storage_blob.blob]

  settings = <<SETTINGS
 {
  "fileUris": ["https://${azurerm_storage_account.storage_account.name}.blob.core.windows.net/storage-container/IIS_Config.ps1"],
   "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config.ps1"
 }
SETTINGS

}

resource "azurerm_network_security_group" "win_app_nsg" {
  name                = "winvm-nsg"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

# Creating a rule to allow traffic on port 80
  security_rule {
    name                       = "Allow_HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.subnet1.id
  network_security_group_id = azurerm_network_security_group.win_app_nsg.id
  depends_on = [azurerm_network_security_group.win_app_nsg]
}
#############################################################################################################################

# Creating a Load balancer to route the traffic to 2 VMs in a backend pool and,
# create a health probe and Load balancing rule. 
# No Virtualmachine scale set

resource "azurerm_network_interface" "nic_app1" {
  name                = "app1-network-interface"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet2.id
    private_ip_address_allocation = "Dynamic"
  }
  depends_on = [azurerm_virtual_network.virtual_network]
}

  resource "azurerm_network_interface" "nic_app2" {
  name                = "app2-network-interface"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet2.id
    private_ip_address_allocation = "Dynamic"
  }

  depends_on = [azurerm_virtual_network.virtual_network]
}

resource "azurerm_windows_virtual_machine" "app_vm1" {
  name                  = "app1-vm"
  resource_group_name   = azurerm_resource_group.resource_group.name
  location              = azurerm_resource_group.resource_group.location
  network_interface_ids = [azurerm_network_interface.nic_app1.id]
  size                  = "Standard_F2"
  admin_username        = "adminuser"
  admin_password        = azurerm_key_vault_secret.win_vm_password.value
  availability_set_id   = azurerm_availability_set.availability_set.id
  #zone               = "1"
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [
    azurerm_network_interface.nic_app1, 
    azurerm_availability_set.availability_set,
    azurerm_key_vault_secret.win_vm_password
    ]
}

resource "azurerm_windows_virtual_machine" "app2_vm" {
  name                  = "app2-vm"
  resource_group_name   = azurerm_resource_group.resource_group.name
  location              = azurerm_resource_group.resource_group.location
  network_interface_ids = [azurerm_network_interface.nic_app2.id]
  size                  = "Standard_F2"
  admin_username        = "adminuser"
  admin_password        = azurerm_key_vault_secret.win_vm_password.value
  availability_set_id   = azurerm_availability_set.availability_set.id
  #zone               = "2"
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [
    azurerm_network_interface.nic_app2, 
    azurerm_availability_set.availability_set,
    azurerm_key_vault_secret.win_vm_password
    ]
}

resource "azurerm_network_security_group" "app_nsg" {
  name                = "app-nsg"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

# Creating a rule to allow traffic on port 80
  security_rule {
    name                       = "Allow_HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app_nsg_association" {
  subnet_id                 = azurerm_subnet.subnet2.id
  network_security_group_id = azurerm_network_security_group.app_nsg.id
  depends_on = [azurerm_network_security_group.app_nsg]
}

# Public IP address is going to be assigned to the Load Balancer
resource "azurerm_public_ip" "load_ip" {
  name                = "lb-public-ip"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  allocation_method   = "Static"
  sku = "Standard"
}

# Defining Load balancer
resource "azurerm_lb" "app_load_balancer" {
  name                = "app-load-balancer"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.load_ip.id
  }
  sku = "Standard"
  sku_tier = "Regional"
  depends_on = [azurerm_public_ip.load_ip]
}

# Load balancer Backend address pool
resource "azurerm_lb_backend_address_pool" "app_pool" {
  loadbalancer_id = azurerm_lb.app_load_balancer.id
  name            = "PoolA"

  depends_on = [azurerm_lb.app_load_balancer]
}

# Add Private ip addresses of the 2 VMs on to the backend address pool
resource "azurerm_lb_backend_address_pool_address" "app_vm1_address" {
  name                    = "app-vm1-address"
  backend_address_pool_id = azurerm_lb_backend_address_pool.app_pool.id
  virtual_network_id      = azurerm_virtual_network.virtual_network.id
  ip_address              = azurerm_network_interface.nic_app1.private_ip_address
  depends_on = [azurerm_lb_backend_address_pool.app_pool]
}

resource "azurerm_lb_backend_address_pool_address" "app_vm2_address" {
  name                    = "app-vm2-address"
  backend_address_pool_id = azurerm_lb_backend_address_pool.app_pool.id
  virtual_network_id      = azurerm_virtual_network.virtual_network.id
  ip_address              = azurerm_network_interface.nic_app2.private_ip_address
  depends_on = [azurerm_lb_backend_address_pool.app_pool]
}

# Define Health Probe
resource "azurerm_lb_probe" "lb_health_probe" {
  loadbalancer_id = azurerm_lb.app_load_balancer.id
  name            = "lb-health-probe"
  port            = 80
}

# Deploy Load Balancer Rule
resource "azurerm_lb_rule" "lb_rule" {
  loadbalancer_id                = azurerm_lb.app_load_balancer.id
  name                           = "lb-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend-ip"
  backend_address_pool_ids = [ azurerm_lb_backend_address_pool.app_pool.id ]
  probe_id = azurerm_lb_probe.lb_health_probe.id
  depends_on = [azurerm_lb.app_load_balancer]
}

# Configure Azure Public DNS Zone.(Azure does not support creation of domain name. Doman names can be purchased by a third party/external domain provider)
# Once the Domain name is available ensure to change the settings there to point to the DNS Zone that we have on the Azure platform
# Using Azure DNS zone we can manage the records of the existing Domains
resource "azurerm_dns_zone" "vpcloudazure_com" {
  name                = "vpcloudazure.com"
  resource_group_name = azurerm_resource_group.resource_group.name
}

output "server_names" {
  value=azurerm_dns_zone.vpcloudazure_com.name_servers
}

resource "azurerm_dns_a_record" "lb_dns_a_record" {
  name                = "www"
  zone_name           = azurerm_dns_zone.vpcloudazure_com.name
  resource_group_name = azurerm_resource_group.resource_group.name
  ttl                 = 300
  records             = [azurerm_public_ip.load_ip.ip_address]
}
######################################################################################################################################################################

# Deployment of Load balancer for the Virtual machine scale set

# Public ip will be assigned to the load balancer
resource "azurerm_public_ip" "vmss_load_ip" {
  name                = "lb-vmss-public-ip"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  allocation_method   = "Static"
  sku = "Standard"
}

# Defining Load balancer
resource "azurerm_lb" "vmss_load_balancer" {
  name                = "vmss-load-balancer"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.vmss_load_ip.id
  }
  sku = "Standard"
  sku_tier = "Regional"
  depends_on = [azurerm_public_ip.vmss_load_ip]
}

# Load balancer Backend address pool
resource "azurerm_lb_backend_address_pool" "scalesetpool" {
  loadbalancer_id = azurerm_lb.vmss_load_balancer.id
  name            = "scalesetpool"

  depends_on = [azurerm_lb.vmss_load_balancer]
}

# Define Health Probe
resource "azurerm_lb_probe" "vmss_lb_probe" {
  loadbalancer_id = azurerm_lb.vmss_load_balancer.id
  name            = "vmss-lb-probe"
  port            = 80
  depends_on = [azurerm_lb.vmss_load_balancer]
}

# Load Balancer Rule
resource "azurerm_lb_rule" "vmss_lb_rule" {
  loadbalancer_id                = azurerm_lb.vmss_load_balancer.id
  name                           = "vmss-lb-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend-ip"
  backend_address_pool_ids = [ azurerm_lb_backend_address_pool.scalesetpool.id ]
  probe_id = azurerm_lb_probe.vmss_lb_probe.id
  depends_on = [azurerm_lb.vmss_load_balancer]
}

resource "azurerm_windows_virtual_machine_scale_set" "vm_scale_set" {
  name                = "vm-ss"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  sku                 = "Standard_F2"
  instances           = 2
  admin_password      = azurerm_key_vault_secret.win_vm_password.value
  admin_username      = "adminuser"
  upgrade_mode        = "Automatic"
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "vmss-network-interface"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.subnet2.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.scalesetpool.id]
    }
  }
  depends_on = [azurerm_virtual_network.virtual_network]
}

resource "azurerm_virtual_machine_scale_set_extension" "scaleset_extension" {
  name                         = "scaleset-extension"
  virtual_machine_scale_set_id = azurerm_windows_virtual_machine_scale_set.vm_scale_set.id
  publisher                    = "Microsoft.Compute"
  type                         = "CustomScriptExtension"
  type_handler_version         = "1.10"
  settings = <<SETTINGS
 {
  "fileUris": ["https://${azurerm_storage_account.storage_account.name}.blob.core.windows.net/storage-container/IIS_Config.ps1"],
   "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config.ps1"
 }
SETTINGS
}
###############################################################################################################################################

#Creation of Application gateway and routing the traffic to the 2 VMs.
# This subnet is used by Appication Gateway resource
resource "azurerm_subnet" "subnetag" {
  name                 = "subnetag"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_network_interface" "web_app1_nic" {
  name                = "webapp1-network-interface"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet2.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "web_app2_nic" {
  name                = "webapp2-network-interface"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet2.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "webapp_vm1" {
  name                  = "webapp-vm1"
  resource_group_name   = azurerm_resource_group.resource_group.name
  location              = azurerm_resource_group.resource_group.location
  network_interface_ids = [azurerm_network_interface.web_app1_nic.id]
  size                  = "Standard_F2"
  admin_username        = "adminuser"
  admin_password        = azurerm_key_vault_secret.win_vm_password.value
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [
    azurerm_network_interface.web_app1_nic,
    azurerm_key_vault_secret.win_vm_password
    ]
}

resource "azurerm_windows_virtual_machine" "webapp_vm2" {
  name                  = "webapp-vm2"
  resource_group_name   = azurerm_resource_group.resource_group.name
  location              = azurerm_resource_group.resource_group.location
  network_interface_ids = [azurerm_network_interface.web_app2_nic.id]
  size                  = "Standard_F2"
  admin_username        = "adminuser"
  admin_password        = azurerm_key_vault_secret.win_vm_password.value
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [
    azurerm_network_interface.web_app2_nic,
    azurerm_key_vault_secret.win_vm_password
    ]
}

resource "azurerm_storage_account" "webappstorageac" {
  name                     = "projectstorage12345ag"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "webappcontainer" {
  name                  = "webappcontainer"
  storage_account_name  = azurerm_storage_account.webappstorageac.name
  container_access_type = "blob"
}

#Uploading IIS Configuration script for image and video files as a blob to the Azure Storage account
resource "azurerm_storage_blob" "IIS_Config_image" {
  name                   = "IIS_Config_image.ps1"
  storage_account_name   = azurerm_storage_account.webappstorageac.name
  storage_container_name = azurerm_storage_container.webappcontainer.name
  type                   = "Block"
  source                 = "IIS_Config_image.ps1"
  depends_on = [azurerm_storage_container.webappcontainer]
}

resource "azurerm_storage_blob" "IIS_Config_video" {
  name                   = "IIS_Config_video.ps1"
  storage_account_name   = azurerm_storage_account.webappstorageac.name
  storage_container_name = azurerm_storage_container.webappcontainer.name
  type                   = "Block"
  source                 = "IIS_Config_video.ps1"
  depends_on = [azurerm_storage_container.webappcontainer]
}

resource "azurerm_virtual_machine_extension" "webapp_vm1_extn" {
  name                 = "webapp-vm1-extension"
  virtual_machine_id   = azurerm_windows_virtual_machine.webapp_vm1.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  depends_on = [azurerm_storage_blob.IIS_Config_image]

  settings = <<SETTINGS
 {
  "fileUris": ["https://${azurerm_storage_account.webappstorageac.name}.blob.core.windows.net/webappcontainer/IIS_Config_image.ps1"],
   "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config_image.ps1"
 }
SETTINGS

}

resource "azurerm_virtual_machine_extension" "webapp_vm2_extn" {
  name                 = "webapp-vm2-extension"
  virtual_machine_id   = azurerm_windows_virtual_machine.webapp_vm2.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  depends_on = [azurerm_storage_blob.IIS_Config_video]

  settings = <<SETTINGS
 {
  "fileUris": ["https://${azurerm_storage_account.webappstorageac.name}.blob.core.windows.net/webappcontainer/IIS_Config_video.ps1"],
   "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS_Config_video.ps1"
 }
SETTINGS
}
# Application Gateway Public IP address
resource "azurerm_public_ip" "app_gateway_ip" {
  name                = "app-gateway-ip"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Application Gateway Deployment
resource "azurerm_application_gateway" "app_gateway" {
  name                = "app-gateway"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
    subnet_id = azurerm_subnet.subnetag.id
  }

  frontend_port {
    name = "front-end-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "front-end-ip-config"
    public_ip_address_id = azurerm_public_ip.app_gateway_ip.id
  }

  backend_address_pool {
    name = "imagepool"
    ip_addresses = [azurerm_network_interface.web_app1_nic.private_ip_address]
  }

  backend_address_pool {
    name = "videopool"
    ip_addresses = [azurerm_network_interface.web_app2_nic.private_ip_address]
  }

  backend_http_settings {
    name                  = "HTTPSetting"
    cookie_based_affinity = "Disabled"
    path                  = ""
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "gateway-listner"
    frontend_ip_configuration_name = "front-end-ip-config"
    frontend_port_name             = "front-end-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "gateway-routing-rule"
    priority                   = 9
    rule_type                  = "PathBasedRouting"
    url_path_map_name          = "RoutingPath"
    http_listener_name         = "gateway-listner"
    backend_http_settings_name = "HTTPSetting"
  }

  url_path_map {
    name = "RoutingPath"
    default_backend_address_pool_name = "videopool"
    default_backend_http_settings_name = "HTTPSetting"

    path_rule {
      name = "VideoRoutingRule"
      backend_address_pool_name = "videopool"
      backend_http_settings_name = "HTTPSetting"
      paths = ["/videos/*",]
    }

    path_rule {
      name = "ImageRoutingRule"
      backend_address_pool_name = "imagepool"
      backend_http_settings_name = "HTTPSetting"
      paths = ["/images/*",]
    }
  }
}
##################################################################################################################################################################################

# MySQL Server Integration with Web App Service.
# Create azure Web App(paas) to host web application. 
# Application code can be directly deployed on to the Azure web app service.
# App service plan also has to be associated with the Azure web app service.
resource "azurerm_app_service_plan" "wappserviceplan" {
  name                = "web-appserviceplan-api"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_app_service" "webapp_service" {
  name                = "webapp-project1"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  app_service_plan_id = azurerm_app_service_plan.wappserviceplan.id
  #   source_control{
  #     repo_url = "https://github.com/Azure-Samples/python-docs-hello-world"
  #     branch = "master"
  #     manual_integration = true
  #     use_mercurial = false
  # }
  depends_on = [azurerm_app_service_plan.wappserviceplan]
}

resource "azurerm_mysql_server" "mysqlserver" {
  name                = "mysqlserver8892"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  administrator_login          = "mysqladmin"
  administrator_login_password = "mysql@123"

  sku_name   = "B_Gen5_2"
  storage_mb = 5120
  version    = "5.7"

  auto_grow_enabled                 = true
  backup_retention_days             = 7
  geo_redundant_backup_enabled      = false
  infrastructure_encryption_enabled = false
  public_network_access_enabled     = true
  ssl_enforcement_enabled           = true
  ssl_minimal_tls_version_enforced  = "TLS1_2"
}

resource "azurerm_mysql_database" "mysql_db" {
  name                = "mysql-db"
  resource_group_name = azurerm_resource_group.resource_group.name
  server_name         = azurerm_mysql_server.mysqlserver.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
  depends_on = [azurerm_mysql_server.mysqlserver]
}

# For the Azure mysql database there is a firewall in place, if we want to connect to the mysqldb,
# via internetand via the mysql database server, we need to have a firewall rule in place.

resource "azurerm_mysql_firewall_rule" "mysqls_fwrule" {
  name                = "mysqls_fwrule"
  resource_group_name = azurerm_resource_group.resource_group.name
  server_name         = azurerm_mysql_server.mysqlserver.name
  start_ip_address    = "10.0.0.90"
  end_ip_address      = "10.0.0.90"
  depends_on = [azurerm_mysql_server.mysqlserver]
}