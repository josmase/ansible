import { TerraformStack } from "cdktf";
import { VmQemu, VmQemuConfig } from "../.gen/providers/proxmox/vm-qemu";
import { ProxmoxProvider } from "../.gen/providers/proxmox/provider";

export interface VirtualMachine {
  id: number;
  name: string;
  qemu_os: string;
  description: string;
  target_node: string;
  os_type: string;
  full_clone: boolean;
  template: string;
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

export interface ProxmoxTokenConfig {
  host: string;
  tokenid: string;
  tokenSecret: string;
}

export interface ProxmoxUserConfig {
  host: string;
  user: string;
  password: string;
}

export function createVms(
  stack: TerraformStack,
  virtualMachines: VirtualMachine[],
  config: ProxmoxTokenConfig | ProxmoxUserConfig
) {
  const proxmox = createProvider(stack, config);

  virtualMachines
    .map(virtualMachineToVmQemuConfig)
    .forEach((vm) => new VmQemu(proxmox, vm.id! + vm.name, vm));
}

function createProvider(
  stack: TerraformStack,
  config: ProxmoxTokenConfig | ProxmoxUserConfig
) {
  const base = {
    pmApiUrl: `https://${config.host}:8006/api2/json`,
    pmTlsInsecure: true,
    pmLogEnable: true,
    pmLogFile: "terraform-plugin-proxmox.log",
  };
  const auth = getProxmoxAuth(config);
  return new ProxmoxProvider(stack, "proxmox_provider", { ...base, ...auth });
}

function isProxmoxTokenConfig(
  config: ProxmoxTokenConfig | ProxmoxUserConfig
): config is ProxmoxTokenConfig {
  return "tokenid" in config && "tokenSecret" in config;
}

function getProxmoxAuth(config: ProxmoxTokenConfig | ProxmoxUserConfig) {
  if (isProxmoxTokenConfig(config)) {
    return {
      pmApiTokenId: config.tokenid,
      pmApiTokenSecret: config.tokenSecret,
    };
  } else {
    return {
      pmApiUser: config.user,
      pmApiPass: config.password,
    };
  }
}
function virtualMachineToVmQemuConfig(value: VirtualMachine): VmQemuConfig {
  return {
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
    nameserver: value.dns_servers.join(" "),
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
  };
}
