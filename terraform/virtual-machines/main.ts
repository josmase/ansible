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
    const subnet = "192.168.1";
    const baseMachine = this.defineBaseVm(subnet);
    const machines: VirtualMachine[] = [
      ...this.defineKubernetesKluster(subnet, baseMachine),
      this.defineMediaServer(subnet, baseMachine),
    ];
    return machines;
  }

  defineMediaServer(subnet: string, baseVm: Partial<VirtualMachine>) {
    const { ubuntuTemplateLarge } = this.vmVariables;
    return {
      ...baseVm,
      cores: 4,
      description:
        "Main media server for stuff that is not yet running in kubernetes",
      id: 105,
      ip_address: `${subnet}.105`,
      memory: 2000,
      name: "media-server",
      template: ubuntuTemplateLarge.value,
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
      cores: 6,
      ip_address: `${subnet}.${id}`,
      memory: 6000,
    } as VirtualMachine;
  }

  defineKubernetesNode(
    id: number,
    subnet: string,
    baseVm: Partial<VirtualMachine>
  ): VirtualMachine {
    const { ubuntuTemplateLarge } = this.vmVariables;

    return {
      ...baseVm,
      id: id,
      name: `kubernetes-node-${id}`,
      cores: 6,
      ip_address: `${subnet}.${id}`,
      memory: 20000,
      template: ubuntuTemplateLarge.value,
    } as VirtualMachine;
  }

  defineBaseVm(subnet: string): Partial<VirtualMachine> {
    const {
      cloudInitPassword: cloudInitPass,
      publicSshKey,
      proxmoxNode,
      ubuntuTemplateSmall,
    } = this.vmVariables;
    return {
      automatic_reboot: true,
      cloud_init_pass: cloudInitPass.value,
      cores: 2,
      dns_servers: ["1.1.1.1", "1.0.0.1", "192.168.1.1", "127.0.0.1"],
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
      template: ubuntuTemplateSmall.value,
    };
  }
}

const app = new App();
new MyStack(app, "typescript");
app.synth();
