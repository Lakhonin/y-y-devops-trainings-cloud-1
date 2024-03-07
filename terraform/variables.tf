variable "instance_userdata_username" {
  type        = string
  description = "instance userdata username"
}

variable "instance_userdata_ssh_public_key" {
  type        = string
  description = "instance userdata ssh public key"
}

variable "token" {
  description = "Yandex Cloud security OAuth token"
}

variable "cloud_id" {
  description = "your cloud id"
}

variable "root_zone" {
  type        = string
  description = "root zone"
}
