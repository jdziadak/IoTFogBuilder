import os
from .k3s_node import K3sNode


class K3sControllerNode(K3sNode):
    def __init__(self, username, node_name, ip, phases, password, reinstall):
        super().__init__(username, node_name, ip, phases, password, reinstall)

    def prepare_k3s_config_file(self):
        print("\tPreparing K3s config directory and files.")
        self.ssh.command("mkdir .kube")
        # Append export of K3s config path to the .bashrc file.
        self.ssh.command(f"echo \"export KUBECONFIG=/home/{self.username}/.kube/config\" >> ~/.bashrc")
        # Source to have the variable available in current session
        self.ssh.command("source ~/.bashrc")

    def install_k3s(self, k3s_version, controller_ip, controller_token):
        print('\tInstalling K3s on the controller node.')
        # This is probably redundant but sometimes (with VM) we skip 1st phase so there may be no curl on the node.
        # If already installed, it'll be just skipped.
        self.ssh.sudo_command("apt install -y curl")
        self.ssh.sudo_command(f"curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=\"{k3s_version}\" K3S_KUBECONFIG_MODE=\"644\" INSTALL_K3S_NAME=\"{self.node_name}\" sh -s -")

    def write_final_k3s_config_file(self):
        print("\tCopying k3s.yaml to config directory and setting node's IP address.")
        self.ssh.command(f"cp /etc/rancher/k3s/k3s.yaml /home/{self.username}/.kube/config")

        # sed the localhost IP address (127.0.0.1) and replace with the controller IP
        self.ssh.command(f"sed -i -r \'s/(\\b[0-9]{{1,3}}\\.){{3}}[0-9]{{1,3}}\\b\'/{self.ip}/ /home/{self.username}/.kube/config")

    def get_controller_token(self, controller_token=None):
        controller_token = self.ssh.sudo_command("cat /var/lib/rancher/k3s/server/node-token")[-1].replace('\r', '').replace('\n', '')
        return controller_token

    def helm_install(self):
        self.ssh.command("curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3")
        self.ssh.command("chmod 700 get_helm.sh")
        self.ssh.sudo_command("./get_helm.sh")

    def install_and_setup_samba(self):
        self.ssh.sudo_command("apt install -y samba smbclient")
        self.ssh.command("mkdir sambashare")
        self.ssh.sudo_command("ln -s ~/sambashare /mnt/local_share")
        # Need to manually edit /etc/samba/smb.conf as described in the documentation and apply following commands:
        # sudo service smbd restart
        # sudo ufw allow samba
        # sudo smbpasswd -a <username>

    def send_deployment_files(self):
        self.ssh.command("rm -rf deployments")
        self.ssh.command("mkdir deployments")

        deployment_directories = ['scripts']
        for dir in deployment_directories:
            self.ssh.command(f"mkdir deployments/{dir}")
            for file in os.listdir(f"deployments/{dir}"):
                self.send_file(f"deployments/{dir}/{file}")
        self.ssh.command("chmod +x ~/deployments/scripts/apply-deployments.sh")

    def get_controller_ip(self):
        return self.ip

    def run_deployments(self):
        self.ssh.command("./deployments/scripts/apply-deployments.sh")

    def uninstall_k3s(self):
        self.ssh.sudo_command("/usr/local/bin/$(ls /usr/local/bin | grep k3s | grep uninstall)")

    def __str__(self):
        return f"IP: {self.ip}, name: {self.node_name} - controller"
