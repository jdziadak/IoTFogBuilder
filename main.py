import sys
from K3sConfiguration import k3s_configurator
from versioning import generate_version

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Run as: main.py config-file rpi-password")
        sys.exit(1)
    configurator = k3s_configurator.K3sRpiConfigurator(sys.argv[1], sys.argv[2])
    configurator.configure_nodes()
    version =generate_version()
    print(version)