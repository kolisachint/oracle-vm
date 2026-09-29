variable "tenancy_ocid" {
  type        = string
  description = "OCID of the OCI tenancy"
  sensitive   = true
}

variable "user_ocid" {
  type        = string
  description = "OCID of the IAM user"
  sensitive   = true
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint of the API signing key"
  sensitive   = true
}

variable "private_key_path" {
  type        = string
  description = "Absolute path to the OCI API private key PEM file on the machine running Terraform"
}

variable "region" {
  type        = string
  description = "OCI region identifier, e.g. us-ashburn-1 or eu-frankfurt-1"
}

variable "compartment_ocid" {
  type        = string
  description = "OCID of the compartment to deploy resources into. Use the tenancy OCID for the root compartment."
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content (the full string, not a file path) for VM access"
}

variable "vcn_cidr" {
  type        = string
  description = "CIDR block for the Virtual Cloud Network"
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for the public subnet"
  default     = "10.0.1.0/24"
}

variable "instance_display_name" {
  type        = string
  description = "Display name for the compute instance"
  default     = "hoocowork-vm"
}

variable "availability_domain_index" {
  type        = number
  description = "Zero-based index into the list of Availability Domains. Most single-AD free-tier regions use 0."
  default     = 0
}

variable "instance_shape" {
  type        = string
  description = "Compute shape. VM.Standard.A1.Flex (ARM, up to 4 OCPU / 24 GB free) or VM.Standard.E2.1.Micro (x86, 1 GB) as a fallback when A1 is out of capacity."
  default     = "VM.Standard.A1.Flex"
}

variable "ubuntu_version" {
  type        = string
  description = "Canonical Ubuntu image version to look up for the chosen shape."
  default     = "24.04"
}

variable "boot_volume_size_in_gbs" {
  type        = number
  description = "Boot volume size in GB. Always Free covers 200 GB of block storage in total."
  default     = 100
}

variable "ocpus" {
  type        = number
  description = "Number of OCPUs for a Flex shape (ignored for E2.1.Micro). Always Free limit is 4 total."
  default     = 4
}

variable "memory_in_gbs" {
  type        = number
  description = "RAM in GB for a Flex shape (ignored for E2.1.Micro). Always Free limit is 24 GB total."
  default     = 24
}
