# Adds the topic to kafka container.
# The first argument is name of the kafka pod (i.e. kafka-broker-74bf4dc9c6-7q54f) to exec the command.
# The second is a name of the new topic.
# Example to create topic "books":
#   ./create-topic.sh kafka-broker-74bf4dc9c6-7q54f books
#
kubectl exec $1 -- opt/bitnami/kafka/bin/kafka-topics.sh --create --topic $2 --bootstrap-server localhost:9092 --replication-factor 1 --partitions 1