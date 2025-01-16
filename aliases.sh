# Usefule aliases to work with the cluster. No input arguments.
# Example usage:
#   ./aliases.sh
alias k=kubectl
alias kk=\"kubectl -n kafka\"
alias kp=\"kubectl -n prometheus\"
alias unagent='/usr/local/bin/k3s-agent-uninstall.sh'
alias unmaster='/usr/local/bin/k3s-uninstall.sh'
alias ll='ls -l'
alias cls=clear
alias python=python3
alias py=python3
# alias nodeips='kubectl get nodes -o wide | awk -v OFS='\t\t' '{print $1, $6, $7}''
check_port() {
    sudo ss -lptn "sport = :$1"
}
# Arguments: pod_name, port number, IP address(es)
port_forward() {
    while true;
    do kubectl port-forward $1 $2 --address $3;
    done > /dev/null 2>&1 &
}
