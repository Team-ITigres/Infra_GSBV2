variable "proxmox_api_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type = string
}

variable "proxmox_api_token" {
  type = string
}

variable "target_node" {
  type = string  
}

variable "chemin_cttemplate" {
  description = "chemin iso ct template"
  type = string
  
}

variable "lxc_linux" {
  type = map(object({
    lxc_id = number
    name = string
    cores = number
    memory = number
    disk_size = string
    ipconfig0 = string
    gw = string
    network_bridge = string
  }))
  
}

variable "win_srv" {
  type = map(object({
    name = string
    vmid = number
    ipconfig0 = string
    dns = string
  }))
  
}

variable "opnsenses" {
  type = map(object({
    name               = string
    vmid               = number
    opnsense_template  = string
  }))
}
