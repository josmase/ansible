import { Construct } from "constructs";
import { TerraformResource } from "cdktf";
import { ProxmoxVmQemuConfig } from "./.gen/providers/proxmox/vm-qemu";

interface VirtualMachine {
  id: string;
  name: string;
  qemu_os: string;
  description: string;
  target_node: string;
  os_type: string;
  full_clone: boolean;
  template: boolean;
  memory: number;
  socket: number;
  cores: number;
  ssh_user: string;
  public_ssh_key: string;
  cloud_init_pass: string;
  automatic_reboot: boolean;
  ip_address: string;
  gateway: string;
  dns_servers: string[];
  network_bridge_type: string;
  network_model: string;
  network_firewall: boolean;
}

interface ProxmoxVmQemuProps {
  virtualMachines: { [key: string]: VirtualMachine };
}

export class ProxmoxVmQemuVirtualMachines extends TerraformResource {
  constructor(scope: Construct, name: string, props: ProxmoxVmQemuProps) {
    super(scope, name);

    for (const [key, value] of Object.entries(props.virtualMachines)) {
      new ProxmoxVmQemuConfig(this, key, {
        vmid: value.id,
        name: value.name,
        qemuOs: value.qemu_os,
        desc: value.description,
        targetNode: value.target_node,
        osType: value.os_type,
        fullClone: value.full_clone,
        clone: value.template,
        memory: value.memory,
        sockets: value.socket,
        cores: value.cores,
        sshUser: value.ssh_user,
        sshkeys: value.public_ssh_key,
        ciuser: value.ssh_user,
        ipconfig0: `ip=${value.ip_address}/24,gw=${value.gateway}`,
        cipassword: value.cloud_init_pass,
        automaticReboot: value.automatic_reboot,
        nameserver: value.dns_servers,
        scsihw: "virtio-scsi-pci",
        network: [
          {
            bridge: value.network_bridge_type,
            model: value.network_model,
            mtu: 0,
            queues: 0,
            rate: 0,
            firewall: value.network_firewall,
          },
        ],
        lifecycle: {
          ignoreChanges: ["network", "disk"],
        },
      });
    }
  }
}
