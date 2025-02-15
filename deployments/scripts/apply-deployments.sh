#!/bin/bash

# Function to check if pods in a given namespace are ready
check_pods_ready() {
    namespace=$1
    echo "Checking readiness of pods in namespace: $namespace"
    kubectl wait --namespace $namespace --for=condition=ready pod --all --timeout=600s
    if [ $? -ne 0 ]; then
        echo "Some pods in namespace $namespace are not ready. Restarting the script..."
        exit 1
    fi
}

# Main loop to execute the script and restart if necessary
while true; do
    # Uninstall Helm releases
    helm uninstall rabbitmq-old
    helm uninstall kube-prometheus-stack -n prometheus
    helm uninstall my-release-kafka -n kafka
    helm uninstall my-couchdb -n couchdb
    helm uninstall zookeper -n kafka
    helm uninstall my-node-red -n node-red

    # Delete services
    kubectl delete service rabbit-np
    kubectl delete service node-red-np  -n node-red
    kubectl delete service couchdb-np -n couchdb
    kubectl delete service grafana-np prometheus-server-np -n prometheus

    # Add repos
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add couchdb https://apache.github.io/couchdb-helm/
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add node-red https://schwarzit.github.io/node-red-chart/
    # Update helm repos
    helm repo update

    # Wait for cleanup
    sleep 15

    # Create namespaces for all our designed namespaces
    kubectl create namespace couchdb
    kubectl create namespace kafka
    kubectl create namespace prometheus
    kubectl create namespace node-red

    # Apply Kafka resources for kafka namespace
    helm install zookeper -n kafka oci://registry-1.docker.io/bitnamicharts/zookeeper --version 13.7.1
    touch values-kafka.yaml
    cat >values-kafka.yaml <<EOL
    listenerSecurityProtocolMap: 'PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT,INTERNAL:PLAINTEXT'
    interBrokerListenerName: 'INTERNAL'
    listeners: 'EXTERNAL://0.0.0.0:19092,PLAINTEXT://0.0.0.0:9092,INTERNAL://0.0.0.0:29092'
    advertisedListeners: 'EXTERNAL://192.168.0.154:19092,PLAINTEXT://kafka:9092,INTERNAL://kafka:29092'
    EOL
    helm install -n kafka my-release-kafka bitnami/kafka --version 20.0.5 -f values-kafka.yaml
    rm values-kafka.yaml

    # Apply CouchDB resources
    touch values-couchdb.yaml
    cat >values-couchdb.yaml <<EOL
    adminUsername: dXNlcm5hbWU=
    adminPassword: cGFzc3dvcmQ=
    couchdbConfig:
      couchdb:
        uuid: decafbaddecafbaddecafbaddecafbad
EOL
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
    kubectl expose service kube-prometheus-stack-prometheus --type=NodePort --target-port=9090 --name=prometheus-server-np -n prometheus
    kubectl expose service kube-prometheus-stack-grafana -n prometheus --type=NodePort --target-port=3000 --name=grafana-np
    kubectl expose service rabbitmq-old --type=NodePort --target-port=15672 --name=rabbit-np
    kubectl expose service my-couchdb-svc-couchdb -n couchdb --type=NodePort --target-port=5984 --name couchdb-np
    kubectl expose service my-node-red --type=NodePort --target-port=1880 --name node-red-np -n node-red

    # Patch previously exposed services
    touch values-couchdb.yaml
    cat >values-couchdb.yaml <<EOL
    apiVersion: v1
    kind: Service
    metadata:
      name: couchdb-np
      namespace: couchdb
    spec:
      ports:
        - nodePort: 30984
          port: 5984
EOL
    kubectl apply -f values-couchdb.yaml

    touch values-node-red.yaml
    cat >values-node-red.yaml <<EOL
    apiVersion: v1
    kind: Service
    metadata:
      name: node-red-np
      namespace: node-red
    spec:
      ports:
        - nodePort: 30001
          port: 1880
EOL
    kubectl apply -f values-node-red.yaml

    touch values-grafana.yaml
    cat >values-grafana.yaml <<EOL
    apiVersion: v1
    kind: Service
    metadata:
      name: grafana-np
      namespace: prometheus
    spec:
      ports:
        - nodePort: 30000
          port: 80
EOL
    kubectl apply -f values-grafana.yaml

    touch values-rabbit.yaml
    cat >values-rabbit.yaml <<EOL
    apiVersion: v1
    kind: Service
    metadata:
      name: rabbit-np
    spec:
      ports:
        - nodePort: 31000
          port: 15672
EOL
    kubectl apply -f values-rabbit.yaml

    rm values-rabbit.yaml values-grafana.yaml values-node-red.yaml values-couchdb.yaml

    # Wait for resources in each namespace to be ready
    check_pods_ready "kafka"
    check_pods_ready "couchdb"
    check_pods_ready "prometheus"
    check_pods_ready "node-red"
    check_pods_ready "default"

    echo "All resources are ready!"

    # If all pods are ready, exit the loop
    echo "Script completed successfully."
    exit 0
done
