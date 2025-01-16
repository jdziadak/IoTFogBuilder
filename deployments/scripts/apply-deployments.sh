#!/bin/bash



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

# In line below we create namespaces for all  our designed namespaces
# kubectl create namespace <namespace>
kubectl create namespace couchdb
kubectl create namespace kafka
kubectl create namespace prometheus
kubectl create namespace node-red
# Enable exition on error in bash. Close script on Error
set -e

# Apply Kafka resources for kafka namespace
# Zookeper installation
helm install zookeper -n kafka oci://registry-1.docker.io/bitnamicharts/zookeeper --version 13.7.1
# Create values-kafka.yaml
touch values-kafka.yaml
cat >values-kafka.yaml <<EOL
listenerSecurityProtocolMap: 'PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT,INTERNAL:PLAINTEXT'
interBrokerListenerName: 'INTERNAL'
listeners: 'EXTERNAL://0.0.0.0:19092,PLAINTEXT://0.0.0.0:9092,INTERNAL://0.0.0.0:29092'
advertisedListeners: 'EXTERNAL://192.168.0.154:19092,PLAINTEXT://kafka:9092,INTERNAL://kafka:29092'

EOL
# Install kafka with values-kafka.yaml
helm install -n kafka my-release-kafka bitnami/kafka --version 20.0.5 -f values-kafka.yaml
# Delete values-kafka.yaml
rm values-kafka.yaml
#old way below:
#kubectl apply -f ~/deployments/kafka/kafka-namespace.yaml
#kubectl apply -f ~/deployments/kafka/zookeeper.yaml
#kubectl apply -f ~/deployments/kafka/kafka.yaml
#kubectl apply -f ~/deployments/kafka/kafdrop.yaml

# Apply CouchDB resources
# create values-couchdb.yaml and append to file
touch values-couchdb.yaml
cat >values-couchdb.yaml <<EOL
adminUsername: dXNlcm5hbWU=
adminPassword: cGFzc3dvcmQ=
couchdbConfig:
  couchdb:
    uuid: decafbaddecafbaddecafbaddecafbad
EOL
# Install couchdb with values-couchdb.yaml
helm install -n couchdb my-couchdb couchdb/couchdb --version 4.5.6 -f values-couchdb.yaml
# Delete values-couchdb.yaml
rm values-couchdb.yaml
# old way below:
#kubectl apply -f ~/deployments/couchdb/couchdb-namespace.yaml
#kubectl apply -f ~/deployments/couchdb/couchdb-secret.yaml
#kubectl apply -f ~/deployments/couchdb/couchdb.yaml


# Apply Node-RED resources

helm install my-node-red node-red/node-red --namespace node-red --version 0.34.0
#kubectl apply -f ~/deployments/node-red/node-red-namespace.yaml
#kubectl apply -f ~/deployments/node-red/node-red.yaml

echo 'going to install prometheus'
# Apply prometheus namespace resources
# Install prometheus-kube-stack with values set in CLI
helm install -n prometheus kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 67.9.0 --wait --set defaultRules.create=false --set nodeExporter.enabled=false  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false --set prometheus.prometheusSpec.probeSelectorNilUsesHelmValues=false --set alertmanager.alertmanagerSpec.useExistingSecret=true --set grafana.env.GF_INSTALL_PLUGINS=flant-statusmap-panel --set grafana.adminPassword=prom-operator


echo 'installed prometheus'

# Apply rabbitmq reosurces witihin default namespace
# Install rabbitmq with values set in CLI
helm install rabbitmq-old bitnami/rabbitmq --version 15.2.2 --namespace default --set auth.username=guest --set auth.password=guest --set auth.erlangCookie=secretcookie --set metrics.enabled=true --set metrics.detailed=true --set metrics.serviceMonitor.default.enabled=true --set metrics.serviceMonitor.detailed.enabled=true --set metrics.serviceMonitor.perObject.enabled=true

echo 'installed rabbit'
# Apply rabbitmq cluster-operator that creates custom controller with CRDs (Custom resource definition) that allows managing RabbitMQ clusters
kubectl apply --filename https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml

# Expose CouchDB service as NodePort
#kubectl patch svc my-couchdb-svc-couchdb -n couchdb -p '{'spec':{'type':'NodePort'}}'
#kubectl patch svc my-couchdb-svc-couchdb -n couchdb -p '{'svpec': {'ports': [{'nodePort': 30984, 'port': 5984}]} }' #todo expsoe service

# Expose Prometheus, Grafana, and RabbitMQ as NodePort
kubectl expose service kube-prometheus-stack-prometheus --type=NodePort --target-port=9090 --name=prometheus-server-np -n prometheus
kubectl expose service kube-prometheus-stack-grafana -n prometheus --type=NodePort --target-port=3000 --name=grafana-np
kubectl expose service rabbitmq-old --type=NodePort --target-port=15672 --name=rabbit-np
kubectl expose service my-couchdb-svc-couchdb -n couchdb --type=NodePort --target-port=5984 --name couchdb-np
kubectl expose service my-node-red --type=NodePort --target-port=1880 --name node-red-np -n node-red

# patch previously exposed services
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
