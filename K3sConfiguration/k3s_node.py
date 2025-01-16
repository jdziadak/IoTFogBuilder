from .ssh_controller import NodeSshController
import time


class K3sNode:
    def __init__(self, username, node_name, ip, phases, password, reinstall=False):
        self.node_name = node_name
        self.ip = ip
        self.username = username
        self.connection_failed = False
        self.phases = phases
        self.reinstall = reinstall
        # SSH connection
        print(f"\tConnecting to target node {ip}")
        self.ssh = NodeSshController(ip, username, password)
        if not self.ssh.get_connection_successful():
            self.connection_failed = True

    def did_connection_fail(self):
        return self.connection_failed

    def check_if_running_current_phase(self, phase):
        return phase in self.phases

    def overwrite_firmware_config_files(self, config_files_dir = '/boot/firmware'):
        print("\tAppending required flags to config files.")

        # filename, check for, modify command:
        file_tuples = [
            # /boot/firmware/config.txt
            ("config.txt", 'add arm_64bit=1', "echo \'add arm_64bit=1\' | tee -a config.txt"),
            # /boot/firmware/cmdline.txt
            ("cmdline.txt", "cgroup_enable=memory", "echo $(cat cmdline.txt) cgroup_memory=1 cgroup_enable=memory > cmdline.txt")
        ]

        for file_tuple in file_tuples:
            print(f"\tModifying {config_files_dir}/{file_tuple[0]}", end='')
            # check stdout if flags have not been already set in the file:
            streams = self.ssh.command(f"grep \'{file_tuple[1]}\' {config_files_dir}/{file_tuple[0]}")
            if streams[1].read().decode('utf-8') == '':
                # copy over the file to current working directory, modify and put back
                # easier than cd there and modifying in place
                self.ssh.command(f"cp {config_files_dir}/{file_tuple[0]} .")
                self.ssh.command(f"{file_tuple[2]}")
                self.ssh.sudo_command(f"mv {file_tuple[0]} {config_files_dir}")
                print('. Done')
            else:
                print(f" - flags already present. Skipping.")

    def prepare_k3s_config_file(self):
        # Not applicable for the worker node.
        pass

    def set_ip_tables(self):
        print("\tConfiguring legacy IP tables.", end='')
        self.ssh.sudo_command("iptables -F")
        self.ssh.sudo_command("update-alternatives --set iptables /usr/sbin/iptables-legacy")
        self.ssh.sudo_command("update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy")
        print(" Done.\n\tInstalling missing Ubuntu kernel packages for raspberry (takes up to 10 minutes).")

    def install_required_modules(self):
        # Don't really need to check if these are already installed.
        # If so, the package will just get skipped so we're fine.
        # -y to skip prompt if one wants to install the package
        # curl usually is installed on RPis but make sure for other platforms:

        # Below takes some noticable time (~6 minutes) to complete.
        # DEBIAN_FRONTEND=noninteractive - disables interactive prompt for the reset. Since the prompt is visual
        # it causes the tool to hang for stdout flush despite module getting installed.
        self.ssh.sudo_command("DEBIAN_FRONTEND=noninteractive apt install -y linux-modules-extra-raspi")
        self.ssh.sudo_command("apt install -y curl")

        print('\tDone. \n\tRebooting.')
        self.reboot_and_reconnect()

        self.ssh.sudo_command("apt install -y cifs-utils")

    def helm_install(self):
        pass

    def install_and_setup_samba(self):
        self.ssh.sudo_command("apt install -y samba smbclient")
        self.ssh.sudo_command("sudo mkdir /mnt/local_share")
        # Need to follow manually with:
        # sudo mount -t cifs //<samba-server-ip>/sambashare /mnt/local_share/ -o username=<username>        

    def reboot_and_reconnect(self):
        self.ssh.sudo_command("reboot")
        # Provide some idle delay for raspberry to reboot:
        # TODO remove later: 90 seconds for RPi 2, for newer can be lower (50 for 3B+)
        self.ssh.reconnect(delay=115)

    def install_k3s(self, k3s_version, controller_ip, controller_token):
        print('\tInstalling K3s on the worker node.')
        # curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=1.24.6+k3s1 K3S_TOKEN=K103489246310f39fa47bab6b49983d52b33f7d3324376c574f6085a55c21ea52d2::server:f04768b32e4c90c9792b1ab5dd2e5907 K3S_URL="https://192.168.0.100:6443 K3S_NODE_NAME=agent3"
        self.ssh.sudo_command(f"curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=\"{k3s_version}\" K3S_TOKEN=\"{controller_token}\" K3S_URL=\"https://{controller_ip}:6443\" K3S_NODE_NAME=\"{self.node_name}\" sh -")

    def write_final_k3s_config_file(self):
        pass

    def get_controller_token(self):
        pass

    def send_deployment_files(self):
        pass

    def send_file(self, file_to_send):
        with open(file_to_send) as fts:
            for line in fts.readlines():
                line = line.replace('\r', '').replace('\n', '')
                self.ssh.command(f"echo \"{line}\" >> {file_to_send}")

    def send_and_source_aliases(self):
        self.ssh.command("rm aliases.sh")
        self.send_file("aliases.sh")
        self.ssh.command("echo \"source aliases.sh\" >> ~/.bashrc")

    def run_deployments(self):
        pass

    def uninstall_k3s(self):
        self.ssh.sudo_command("/usr/local/bin/k3s-agent-uninstall.sh")

    def __str__(self):
        return f"IP: {self.ip}, name: {self.node_name} - node"
