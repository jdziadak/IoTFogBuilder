#!/bin/bash

# Function to check if pods in a given namespace are ready
check_pods_ready() {
    namespace=$1
    echo 'Checking readiness of pods in namespace: $namespace'
    kubectl wait --namespace $namespace --for=condition=ready pod --all --timeout=600s
    if [ $? -ne 0 ]; then
        echo 'Some pods in namespace $namespace are not ready. Restarting the script...'
        return 1
    fi
    return 0
}

# Main loop to execute the script and restart if necessary
while true; do
    # Uninstall Helm releases (skip if release is not found)
    helm uninstall rabbitmq-old || true
    helm uninstall kube-prometheus-stack -n prometheus || true
    helm uninstall my-release-kafka -n kafka || true
    helm uninstall my-couchdb -n couchdb || true
    helm uninstall zookeper -n kafka || true
    helm uninstall my-node-red -n node-red || true

    # Delete services (skip if service is not found)
    kubectl delete service rabbit-np || true
    kubectl delete service node-red-np -n node-red || true
    kubectl delete service couchdb-np -n couchdb || true
    kubectl delete service grafana-np prom-np prometheus-server-np -n prometheus || true
    # Add repos
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add couchdb https://apache.github.io/couchdb-helm/
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add node-red https://schwarzit.github.io/node-red-chart/
    helm repo update

    # Wait for cleanup
    sleep 15

    # Create namespaces for all our designed namespaces
    kubectl create namespace couchdb || true
    kubectl create namespace kafka || true
    kubectl create namespace prometheus || true
    kubectl create namespace node-red || true

    # Apply Kafka resources for kafka namespace
    helm install zookeper -n kafka oci://registry-1.docker.io/bitnamicharts/zookeeper --version 13.7.1
    touch values-kafka.yaml
    printf 'listenerSecurityProtocolMap: 'PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT,INTERNAL:PLAINTEXT'\ninterBrokerListenerName: 'INTERNAL'\nlisteners: 'EXTERNAL://0.0.0.0:19092,PLAINTEXT://0.0.0.0:9092,INTERNAL://0.0.0.0:29092'\nadvertisedListeners: 'EXTERNAL://192.168.0.154:19092,PLAINTEXT://kafka:9092,INTERNAL://kafka:29092'\n' > values-kafka.yaml
    helm install -n kafka my-release-kafka bitnami/kafka --version 20.0.5 -f values-kafka.yaml
    rm values-kafka.yaml

    # Apply CouchDB resources
    touch values-couchdb.yaml
    printf 'adminUsername: dXNlcm5hbWU=\nadminPassword: cGFzc3dvcmQ=\ncouchdbConfig:\n  couchdb:\n    uuid: decafbaddecafbaddecafbaddecafbad\n' > values-couchdb.yaml
    helm install -n couchdb my-couchdb couchdb/couchdb --version 4.5.6 -f values-couchdb.yaml
    rm values-couchdb.yaml

    # Apply Node-RED resources
    helm install my-node-red node-red/node-red --namespace node-red --version 0.34.0

    echo 'going to install prometheus'
    # Apply prometheus namespace resources
    helm install -n prometheus kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 67.9.0 --timeout 15m0s --wait --set defaultRules.create=false --set nodeExporter.enabled=false --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false --set prometheus.prometheusSpec.probeSelectorNilUsesHelmValues=false --set alertmanager.alertmanagerSpec.useExistingSecret=true --set grafana.env.GF_INSTALL_PLUGINS=flant-statusmap-panel --set grafana.adminPassword=prom-operator

    echo 'installed prometheus'

    # Apply rabbitmq resources
    helm install rabbitmq-old bitnami/rabbitmq --version 15.2.2 --namespace default --set auth.username=guest --set auth.password=guest --set auth.erlangCookie=secretcookie --set metrics.enabled=true --set metrics.detailed=true --set metrics.serviceMonitor.default.enabled=true --set metrics.serviceMonitor.detailed.enabled=true --set metrics.serviceMonitor.perObject.enabled=true

    echo 'installed rabbit'
    # Apply rabbitmq cluster-operator
    kubectl apply --filename https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml

    # Expose services
    kubectl expose service kube-prometheus-stack-prometheus --type=NodePort --target-port=9090 --name=prom-np -n prometheus
    kubectl expose service kube-prometheus-stack-grafana -n prometheus --type=NodePort --target-port=3000 --name=grafana-np
    kubectl expose service rabbitmq-old --type=NodePort --target-port=15672 --name=rabbit-np
    kubectl expose service my-couchdb-svc-couchdb -n couchdb --type=NodePort --target-port=5984 --name couchdb-np
    kubectl expose service my-node-red --type=NodePort --target-port=1880 --name node-red-np -n node-red

    # Patch previously exposed services
    touch values-couchdb.yaml
    printf 'apiVersion: v1\nkind: Service\nmetadata:\n  name: couchdb-np\n  namespace: couchdb\nspec:\n  ports:\n    - nodePort: 30984\n      port: 5984\n' > values-couchdb.yaml
    kubectl apply -f values-couchdb.yaml

    touch values-node-red.yaml
    printf 'apiVersion: v1\nkind: Service\nmetadata:\n  name: node-red-np\n  namespace: node-red\nspec:\n  ports:\n    - nodePort: 30001\n      port: 1880\n' > values-node-red.yaml
    kubectl apply -f values-node-red.yaml

    touch values-grafana.yaml
    printf 'apiVersion: v1\nkind: Service\nmetadata:\n  name: grafana-np\n  namespace: prometheus\nspec:\n  ports:\n    - nodePort: 30000\n      port: 80\n' > values-grafana.yaml
    kubectl apply -f values-grafana.yaml

    touch values-rabbit.yaml
    printf 'apiVersion: v1\nkind: Service\nmetadata:\n  name: rabbit-np\nspec:\n  ports:\n    - nodePort: 31000\n      port: 15672\n' > values-rabbit.yaml
    kubectl apply -f values-rabbit.yaml

    rm values-rabbit.yaml values-grafana.yaml values-node-red.yaml values-couchdb.yaml

    # Wait for resources in each namespace to be ready
    check_pods_ready 'kafka' || continue
    check_pods_ready 'couchdb' || continue
    check_pods_ready 'prometheus' || continue
    check_pods_ready 'node-red' || continue
    check_pods_ready 'default' || continue

    echo 'All resources are ready!'

    # Print services with NodePorts
	echo 'Listing services with NodePorts:' # Get services in the prometheus namespace 
	 kubectl get svc -n prometheus -o custom-columns='SERVICE:.metadata.name,NODEPORT:.spec.ports[*].nodePort' | grep -i '\-np' | column -t | awk '{print $1, '\t\t', $2}'
	 # Get services in the node-red namespace
	 kubectl get svc -n node-red -o custom-columns='SERVICE:.metadata.name,NODEPORT:.spec.ports[*].nodePort' | grep -i '\-np' | column -t | awk '{print $1, '\t\t', $2}' 
	 # Get services in the couchdb namespace 
	 kubectl get svc -n couchdb -o custom-columns='SERVICE:.metadata.name,NODEPORT:.spec.ports[*].nodePort' | grep -i '\-np' | column -t | awk '{print $1, '\t\t', $2}' 
	 printf '!!! Remember that if you want to login to CouchDB you need to go to https://IP_ADDRESS_OF_CONTROLLER:30984/_utils !!!\n' 
     # Get services in the kafka namespace 
	 kubectl get svc -n kafka -o custom-columns='SERVICE:.metadata.name,NODEPORT:.spec.ports[*].nodePort' | grep -i '\-np' | column -t | awk '{print $1, '\t\t', $2}' 
	 # Get services in the default namespace
	 kubectl get svc -n default -o custom-columns='SERVICE:.metadata.name,NODEPORT:.spec.ports[*].nodePort' | grep -i '\-np' | column -t | awk '{print $1, '\t\t', $2}' 

    # If all pods are ready, exit the loop
    echo 'Script completed successfully.'
    exit 0
done

