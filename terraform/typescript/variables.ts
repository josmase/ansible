import { TerraformStack, TerraformVariable, VariableType } from "cdktf";

export type VmVariables = ReturnType<typeof vmVariables>

export function vmVariables(stack: TerraformStack) {
  return {
    cloudInitPassword: new TerraformVariable(stack, "cloud_init_password", {
      description: "Password for the default user created by cloud-init",
      type: VariableType.STRING,
    }),
    proxmoxHost: new TerraformVariable(stack, "proxmox_host", {
      description: "Ip address or hostname of the proxmox machine",
      type: VariableType.STRING,
    }),
    proxmoxNode: new TerraformVariable(stack, "proxmox_node", {
      description: "Name of the proxmox node",
      type: VariableType.STRING,
    }),
    proxmoxUser: new TerraformVariable(stack, "proxmox_user", {
      description: "Token id for the proxmox user",
      sensitive: true,
      type: VariableType.STRING,
    }),
    proxmoxPassword: new TerraformVariable(stack, "proxmox_password", {
      description: "Token secret for the proxmox user",
      sensitive: true,
      type: VariableType.STRING,
    }),
    proxmoxStorage: new TerraformVariable(stack,"proxmox_storage",{
      description: "The name of the storage space to put all container disks in",
      type: VariableType.STRING
    }),
    publicSshKey: new TerraformVariable(stack, "public_ssh_key", {
      default:
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCaXqMUptEiKLs/Mgkttl4FXD/zvhE3u3SAuUwJneq29ubhogO2H3AjodpAc4Sfo0cVCGrfwyceR22Q4r5oAQ1Z4ucsKw26bkrQ4G6QbW49meDVmRou8ToTJoNyoOlAZggLtZA9gkASKQipvp8AVNxR5HFm7tIx27GQhgRoE87rcAEVz1qvFs8tXGGXxRUK0DeF4IuCJprv/1RV+5zFMk7TX26/TU7i1kjmOGJ4FOIbtDWllMjv7AAjS7jC4vV/GgqocGKR/men+cluFW4rqqKQshzzzh/KvwTJKBd2NUpn/y4D+HEmVx91TuIwv2SQchAO6h1W4ZScyW7P3xKhNNEGzYk6Oh/5Jew8cUskXO9Zv3iaAaU/iHqsK+09cqV+qyL4MOVt3Z+QlAnuLPmOe5qTAaK/8Vsk0UrOn3g4pyVLdBBybSz8Omrm25Fr6qJI3D++Raq9p9IYSysx+8VFcng6IO4Dcd0Vrgsw+cZ3WReeIpKuZtsViA1UqkImhVrab9AdO3j5O2FXqQPqfUYJr7wLttt6YNoxdNF1MauojFcBjkrOeOamKngpCOADi8NR6lhFLlWclcQ75qFV2eP2J4IHqlY2sFFm20TerIi6Aoykh41w6lBujsMKD+6yvwmYmyMm7WqXZVrKS1g6WZRd3gQyreOMi4oezmAILA3sg5VQJQ==",
    }),
    ubuntuTemplate20G: new TerraformVariable(stack, "ubuntu_template_20G", {
      description:
        "Name of template image used for cloud init of ubuntu image. With 20G initial disk. As I found no other way to get that working.",
      type: VariableType.STRING,
    }),
    ubuntuTemplate300G: new TerraformVariable(stack, "ubuntu_template_300G", {
      description: "Name of template image used for cloud init of ubuntu image",
      type: VariableType.STRING,
    }),
  };
}
