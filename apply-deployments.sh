#!/bin/bash

# Uninstall Helm releases
helm uninstall my-release
helm uninstall kube-prometheus-stack -n prometheus

# Delete services
kubectl delete service rabbit-np
kubectl delete service grafana-np prometheus-server-np -n prometheus

# Wait for resources to be cleaned up
echo "Sleeping 180 seconds to allow for resource cleanup..."
sleep 180

# Apply Kafka resources
kubectl apply -f ~/deployments/kafka/kafka-namespace.yaml
kubectl apply -f ~/deployments/kafka/zookeeper.yaml
kubectl apply -f ~/deployments/kafka/kafka.yaml
kubectl apply -f ~/deployments/kafka/kafdrop.yaml

# Apply CouchDB resources
kubectl apply -f ~/deployments/couchdb/couchdb-namespace.yaml
kubectl apply -f ~/deployments/couchdb/couchdb-secret.yaml
kubectl apply -f ~/deployments/couchdb/couchdb.yaml

# Apply Node-RED resources
kubectl apply -f ~/deployments/node-red/node-red-namespace.yaml
kubectl apply -f ~/deployments/node-red/node-red.yaml

# Add and update Prometheus Helm repository, then install Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install -n prometheus kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --install \
  --wait \
  --set "defaultRules.create=false" \
  --set "nodeExporter.enabled=false" \
  --set "prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false" \
  --set "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false" \
  --set "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false" \
  --set "prometheus.prometheusSpec.probeSelectorNilUsesHelmValues=false" \
  --set "alertmanager.alertmanagerSpec.useExistingSecret=true" \
  --set "grafana.env.GF_INSTALL_PLUGINS=flant-statusmap-panel" \
  --set "grafana.adminPassword=prom-operator"

# Install RabbitMQ using Helm
helm install rabbitmq bitnami/rabbitmq \
  --namespace default \
  --set auth.username=guest \
  --set auth.password=guest \
  --set auth.erlangCookie=secretcookie \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true \
  --set metrics.detailed=tr

# Apply rabbitmq cluster-operator that allows clsuter
kubectl apply --filename https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml

# Expose CouchDB service as NodePort
kubectl patch svc couchdb-service -n couchdb -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc couchdb-service -n couchdb -p '{"spec": {"ports": [{"nodePort": 30984, "port": 5984}]} }'

# Expose Prometheus, Grafana, and RabbitMQ as NodePort
kubectl expose service kube-prometheus-stack-prometheus --type=NodePort --target-port=9090 --name=prometheus-server-np -n prometheus
kubectl expose service kube-prometheus-stack-grafana -n prometheus --type=NodePort --target-port=3000 --name=grafana-np
kubectl expose service my-release-rabbitmq --type=NodePort --target-port=15672 --name=rabbit-np

kubectl patch svc rabbit-np --type='merge' -p '{"spec": {"ports": [{"name": "management", "nodePort": 31000}]}}'
kubectl patch svc grafana-np -n prometheus -p '{\"spec\":{\"type\":\"NodePort\"}}'
kubectl patch svc grafana-np -n prometheus -p '{\"spec\": {\"ports\": [{\"nodePort\": 30000, \"port\": 80}]} }'
kubectl patch svc rabbit-np -p '{\"spec\":{\"type\":\"NodePort\"}}'
kubectl patch svc rabbit-np -p '{\"spec\": {\"ports\": [{\"nodePort\": 31000, \"port\": 15672}]} }'
kubectl patch svc rabbit-np -p '{\"spec\": {\"ports\": [{\"nodePort\": 30985, \"port\": 5672}]} }'
