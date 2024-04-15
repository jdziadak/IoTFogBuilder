# Applies all listed deployments. No input arguments.
# Example usage:
#   ./apply-deployments.sh
# Kafka
kubectl apply -f ~/deployments/kafka/kafka-namespace.yaml
kubectl apply -f ~/deployments/kafka/zookeeper.yaml
kubectl apply -f ~/deployments/kafka/kafka.yaml
kubectl apply -f ~/deployments/kafka/kafdrop.yaml
# CouchDB
kubectl apply -f ~/deployments/couchdb/couchdb-namespace.yaml
kubectl apply -f ~/deployments/couchdb/couchdb-secret.yaml
kubectl apply -f ~/deployments/couchdb/couchdb.yaml
# NodeRED
kubectl apply -f ~/deployments/node-red/node-red-namespace.yaml
kubectl apply -f ~/deployments/node-red/node-red.yaml
# Prom-kube-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus --namespace prometheus --create-namespace prometheus-community/kube-prometheus-stack 
# rabbit
helm install my-release oci://registry-1.docker.io/bitnamicharts/rabbitmq --set auth.username="guest" --set auth.password="guest" --set metrics.enabled=true
sleep 60
# patch helm deployments
kubectl patch svc couchdb-service -n couchdb -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc couchdb-service -n couchdb -p '{"spec": {"ports": [{"nodePort": 30984, "port": 5984}]} }'
kubectl patch svc prometheus-grafana -n prometheus -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc prometheus-grafana -n prometheus -p '{\"spec\": {\"ports\": [{\"nodePort\": 30000, \"port\": 80}]} }'
kubectl patch svc my-release-rabbitmq -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc my-release-rabbitmq -p '{"spec": {"ports": [{"nodePort": 31000, "port": 15672}]} }'
