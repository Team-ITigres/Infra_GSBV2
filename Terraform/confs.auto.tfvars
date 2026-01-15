lxc_linux = {
  "Adguard" = {
    lxc_id = 113
    name = "Adguard"
    cores = 1
    memory = 1024
    ipconfig0 = "172.16.0.3/24"
    gw = "172.16.0.254"
    disk_size = 10
    network_bridge = "vmbr0"
    }

    "Stack-Web" = {
    lxc_id = 114
    name = "Stack-Web"
    cores = 1
    memory = 1024
    ipconfig0 = "172.16.0.4/24"
    gw = "172.16.0.254"
    disk_size = 10
    network_bridge = "vmbr0"
    }

    "Stack-App" = {
    lxc_id = 115
    name = "Stack-App"
    cores = 2
    memory = 2048
    ipconfig0 = "172.16.0.5/24"
    gw = "172.16.0.254"
    disk_size = 10
    network_bridge = "vmbr0"
    }

    "Dockermail" = {
    lxc_id = 116
    name = "Dockermail"
    cores = 2
    memory = 2048
    ipconfig0 = "172.16.0.6/24"
    gw = "172.16.0.254"
    disk_size = 20
    network_bridge = "vmbr0"
    }

    "SFTPGO" = {
    lxc_id = 120
    name = "SFTPGO"
    cores = 2
    memory = 2048
    ipconfig0 = "172.16.69.2/29"
    gw = "172.16.69.1"
    disk_size = 20
    network_bridge = "DMZ"
    }

    "ProxmoxBackup" = {
    lxc_id = 130
    name = "ProxmoxBackup"
    cores = 2
    memory = 2048
    ipconfig0 = "172.16.31.1/30"
    gw = "172.16.31.2"
    disk_size = 100
    network_bridge = "vmbr2"
    vlan_id = 301
    }
}

win_srv = {
  "WinSRV01" = {
    name = "WinSRV01"
    vmid = 201
    ipconfig0 = "172.16.0.1/24"
    gw = "172.16.0.254"
    dns = "8.8.8.8"

    }

  "WinSRV02" = {
    name = "WinSRV02"
    vmid = 202
    ipconfig0 = "172.16.0.2/24"
    gw = "172.16.0.254"
    dns = "172.16.0.1"

    }
}

# opnsenses = {
#   "OPNsense-Master" = {
#     name = "OPNsense-Master"
#     vmid = 301
#     clone_id = 2100
#     net0  ="172.16.0.10/24"
#     net0_gateway = "172.16.0.254"
#     net1  ="192.168.150.252/24"
#     net2  ="192.168.151.1/29"
#     net3  ="10.10.0.8/28"
#     }

#   "OPNsense-Backup" = {
#     name = "OPNsense-Backup"
#     vmid = 302
#     clone_id = 2101
#     net0  ="172.16.0.11/24"
#     net0_gateway = "172.16.0.254"
#     net1  ="192.168.150.253/24"
#     net2  ="192.168.151.2/29"
#     net3  ="10.10.0.9/28"
#     }
# }