import { Construct } from "constructs";
import { App, TerraformStack } from "cdktf";
import { VmVariables, vmVariables } from "./variables";
import { VirtualMachine, createVms } from "./proxmox/proxmox";

class MyStack extends TerraformStack {
  vmVariables: VmVariables;
  constructor(scope: Construct, id: string) {
    super(scope, id);
    this.vmVariables = vmVariables(this);

    const { proxmoxHost, proxmoxTokenId, proxmoxTokenSecret } =
      this.vmVariables;
    console.dir(this.vmVariables);
    createVms(this, this.defineMachines(), {
      host: proxmoxHost.value,
      tokenid: proxmoxTokenId.value,
      tokenSecret: proxmoxTokenSecret.value,
    });
  }

  private defineMachines() {
    const subnet = "192.168.0";
    const baseMachine = this.defineBaseVm(subnet);
    const machines: VirtualMachine[] = [
      ...this.defineKubernetesKluster(subnet, baseMachine),
      this.defineMediaServer(subnet, baseMachine),
      this.defineUtilityServer(subnet, baseMachine),
    ];
    return machines;
  }

  defineUtilityServer(subnet: string, baseVm: Partial<VirtualMachine>) {
    return {
      ...baseVm,
      description:
        "For running utils that should always be running, for example vpn. So that all other VMs can safely be restarted without risk of being locked out.",
      id: 110,
      ip_address: `${subnet}.110`,
      name: "utils",
      on_boot: true
    } as VirtualMachine;
  }

  defineMediaServer(subnet: string, baseVm: Partial<VirtualMachine>) {
    const { ubuntuTemplate300G } = this.vmVariables;
    return {
      ...baseVm,
      cores: 10,
      description:
        "Main media server for stuff that is not yet running in kubernetes",
      id: 105,
      ip_address: `${subnet}.105`,
      memory: 9000,
      name: "media-server",
      template: ubuntuTemplate300G.value,
    } as VirtualMachine;
  }

  defineKubernetesKluster(
    subnet: string,
    baseVm: Partial<VirtualMachine>
  ): VirtualMachine[] {
    const master = [201, 202, 203].map((id) =>
      this.defineKubernetesMaster(id, subnet, baseVm)
    );
    const node = [204, 205, 206].map((id) =>
      this.defineKubernetesNode(id, subnet, baseVm)
    );
    return [...master, ...node];
  }

  defineKubernetesMaster(
    id: number,
    subnet: string,
    baseVm: Partial<VirtualMachine>
  ): VirtualMachine {
    return {
      ...baseVm,
      id: id,
      name: `kubernetes-master-${id}`,
      ip_address: `${subnet}.${id}`,
      memory: 3000,
    } as VirtualMachine;
  }

  defineKubernetesNode(
    id: number,
    subnet: string,
    baseVm: Partial<VirtualMachine>
  ): VirtualMachine {
    return {
      ...baseVm,
      id: id,
      name: `kubernetes-node-${id}`,
      cores: 4,
      ip_address: `${subnet}.${id}`,
      memory: 6000,
    } as VirtualMachine;
  }

  defineBaseVm(subnet: string): Partial<VirtualMachine> {
    const {
      cloudInitPassword: cloudInitPass,
      publicSshKey,
      proxmoxNode,
      ubuntuTemplate20G,
    } = this.vmVariables;
    return {
      automatic_reboot: true,
      cloud_init_pass: cloudInitPass.value,
      cores: 2,
      dns_servers: ["1.1.1.1", "1.0.0.1", "192.168.0.1", "127.0.0.1"],
      full_clone: true,
      gateway: `${subnet}.1`,
      memory: 2048,
      network_bridge_type: "vmbr0",
      network_firewall: false,
      network_model: "virtio",
      os_type: "cloud-init",
      public_ssh_key: publicSshKey.value,
      qemu_os: "other",
      socket: 1,
      ssh_user: "ubuntu",
      target_node: proxmoxNode.value,
      template: ubuntuTemplate20G.value,
    };
  }
}

const app = new App();
new MyStack(app, "typescript");
app.synth();
