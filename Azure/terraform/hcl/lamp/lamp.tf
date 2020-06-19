#################################################################
# Terraform template that will deploy LAMP in Microsoft Azure
#    * Virtual Machine - Ubuntu 16.04, Apache 2 and PHP 7.0
#    * SQL Server v12 Database Service
#
# Version: 1.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Licensed Materials - Property of IBM
#
# ©Copyright IBM Corp. 2017.
#
#################################################################

#########################################################
# Define the Azure provider
#########################################################
provider "azurerm" { version = "~> 1.0" }

#########################################################
# Helper module for tagging
#########################################################
module "camtags" {
  source = "../Modules/camtags"
}

#########################################################
# Define the variables
#########################################################
variable "azure_region" {
  description = "Azure region to deploy infrastructure resources"
  default     = "West US"
}

variable "name_prefix" {
  description = "Prefix of names for Azure resources"
  default     = "azure"
}
  
variable "vm_size" {
  description = "The size of the VM to create."
  default = "Standard_A2"
}
  
variable "count" {
  default = "1"
}
  
variable "attach_extra_disk" {
  default = "false"
  description = "Attach an additional disk to the instance."
}

variable "admin_user" {
  description = "Name of an administrative user to be created in virtual machine and SQL service in this deployment"
  default     = "ibmadmin"
}

variable "admin_user_password" {
  description = "Password of the newly created administrative user"
}

variable "user_public_key" {
  description = "Public SSH key used to connect to the virtual machine"
  default     = "None"
}


#########################################################
# Deploy the network resources
#########################################################
resource "random_id" "default" {
  byte_length = "4"
}

resource "azurerm_resource_group" "default" {
  name     = "${var.name_prefix}-${random_id.default.hex}-rg"
  location = "${var.azure_region}"
  tags     = "${module.camtags.tagsmap}"
}

resource "azurerm_virtual_network" "default" {
  name                = "${var.name_prefix}-${random_id.default.hex}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = "${var.azure_region}"
  resource_group_name = "${azurerm_resource_group.default.name}"
}

resource "azurerm_subnet" "web" {
  name                 = "${var.name_prefix}-subnet-${random_id.default.hex}-web"
  resource_group_name  = "${azurerm_resource_group.default.name}"
  virtual_network_name = "${azurerm_virtual_network.default.name}"
  address_prefix       = "10.0.1.0/24"
}

resource "azurerm_public_ip" "web" {
  name                         = "${var.name_prefix}-${random_id.default.hex}-web-pip"
  location                     = "${var.azure_region}"
  resource_group_name          = "${azurerm_resource_group.default.name}"
  allocation_method 		   = "Static"
  tags                         = "${module.camtags.tagsmap}"
}

resource "azurerm_network_security_group" "web" {
  name                = "${var.name_prefix}-${random_id.default.hex}-web-nsg"
  location            = "${var.azure_region}"
  resource_group_name = "${azurerm_resource_group.default.name}"
  tags                = "${module.camtags.tagsmap}"

  security_rule {
    name                       = "ssh-allow"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "custom-tcp-allow"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "web" {
  name                      = "${var.name_prefix}-${random_id.default.hex}-web-nic1"
  location                  = "${var.azure_region}"
  resource_group_name       = "${azurerm_resource_group.default.name}"
  network_security_group_id = "${azurerm_network_security_group.web.id}"
  tags                      = "${module.camtags.tagsmap}"

  ip_configuration {
    name                          = "${var.name_prefix}-${random_id.default.hex}-web-nic1-ipc"
    subnet_id                     = "${azurerm_subnet.web.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.web.id}"
  }
}

#########################################################
# Deploy the storage resources
#########################################################
resource "azurerm_storage_account" "default" {
  name                		= "${format("st%s",random_id.default.hex)}"
  resource_group_name 		= "${azurerm_resource_group.default.name}"
  location            		= "${var.azure_region}"
  account_tier        		= "Standard"  
  account_replication_type  = "LRS"
  
  tags                = "${module.camtags.tagsmap}"
  
}

resource "azurerm_storage_container" "default" {
  name                  = "default-container"
  resource_group_name   = "${azurerm_resource_group.default.name}"
  storage_account_name  = "${azurerm_storage_account.default.name}"
  container_access_type = "private"
}

#########################################################
# Deploy the virtual machine resource
#########################################################
resource "azurerm_virtual_machine" "web" {
  count                 = "${var.user_public_key != "None" ? 1 : 0}"
  name                  = "${var.name_prefix}-web-${random_id.default.hex}-vm"
  location              = "${var.azure_region}"
  resource_group_name   = "${azurerm_resource_group.default.name}"
  network_interface_ids = ["${azurerm_network_interface.web.id}"]
  vm_size               = "${var.vm_size}"
  tags                  = "${module.camtags.tagsmap}"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name          = "${var.name_prefix}-${random_id.default.hex}-web-os-disk1"
    vhd_uri       = "${azurerm_storage_account.default.primary_blob_endpoint}${azurerm_storage_container.default.name}/${var.name_prefix}-${random_id.default.hex}-web-os-disk1.vhd"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }
  
#  storage_data_disk {
#   name              = "${var.name_prefix}-${random_id.default.hex}-web-data-disk1"
#   managed_disk_type = "Standard_LRS"
#   create_option     = "Empty"
#   lun               = 0
#   disk_size_gb      = "1023"
# }

# storage_data_disk {
#   name            = "${azurerm_managed_disk.external.*.name}"
#   managed_disk_id = "${azurerm_managed_disk.external.*.id}"
#   create_option   = "Attach"
#   lun             = 1
#   disk_size_gb    = "${azurerm_managed_disk.external.*.disk_size_gb}"
# }

  os_profile {
    computer_name  = "${var.name_prefix}-${random_id.default.hex}-web"
    admin_username = "${var.admin_user}"
    admin_password = "${var.admin_user_password}"
  }

  os_profile_linux_config {
    disable_password_authentication = false

    ssh_keys {
      path     = "/home/${var.admin_user}/.ssh/authorized_keys"
      key_data = "${var.user_public_key}"
    }
  }
}
  
resource "azurerm_virtual_machine" "web-alternative" {
  count                 = "${var.user_public_key == "None" ? 1 : 0}"
  name                  = "${var.name_prefix}-${random_id.default.hex}-web-vm"
  location              = "${var.azure_region}"
  resource_group_name   = "${azurerm_resource_group.default.name}"
  network_interface_ids = ["${azurerm_network_interface.web.id}"]
  vm_size               = "${var.vm_size}"
  tags                  = "${module.camtags.tagsmap}"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name          = "${var.name_prefix}-${random_id.default.hex}-web-os-disk1"
    vhd_uri       = "${azurerm_storage_account.default.primary_blob_endpoint}${azurerm_storage_container.default.name}/${var.name_prefix}-${random_id.default.hex}-web-os-disk1.vhd"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }
  
#  storage_data_disk {
#   name              = "${var.name_prefix}-${random_id.default.hex}-web-data-disk1"
#   managed_disk_type = "Standard_LRS"
#   create_option     = "Empty"
#   lun               = 0
#   disk_size_gb      = "1023"
# }

# storage_data_disk {
#   name            = azurerm_managed_disk.external.*.name
#   managed_disk_id = azurerm_managed_disk.external.*.id
#   create_option   = "Attach"
#   lun             = 1
#   disk_size_gb    = "${azurerm_managed_disk.external.*.disk_size_gb}"
# }
  
  os_profile {
    computer_name  = "${var.name_prefix}-${random_id.default.hex}-web"
    admin_username = "${var.admin_user}"
    admin_password = "${var.admin_user_password}"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}
  
resource "azurerm_managed_disk" "external" {
  name                 = "${var.name_prefix}-${random_id.default.hex}-web-data-disk1"
  location             = "${var.azure_region}"
  resource_group_name  = "${azurerm_resource_group.default.name}"
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "10"
}

resource "azurerm_virtual_machine_data_disk_attachment" "external" {
  managed_disk_id    = "${azurerm_managed_disk.external.id}"
  virtual_machine_id = "${azurerm_virtual_machine.web-alternative.id}"
  lun                = "0"
  caching            = "ReadWrite"
}

#########################################################
# Output
#########################################################
output "lamp_web_vm_public_ip" {
  value = "${azurerm_public_ip.web.ip_address}"
}

output "lamp_web_vm_private_ip" {
  value = "${azurerm_network_interface.web.private_ip_address}"
}

