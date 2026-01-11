#!/bin/bash
# Скрипт инициализации и настройки Vault
# Выполнять после развертывания Vault в кластере

set -e

echo "=== Инициализация HashiCorp Vault ==="

# Ожидание готовности Vault pod
echo "Ожидание готовности Vault..."
kubectl wait --for=condition=ready pod -l app=vault -n vault --timeout=300s

# Получение имени пода Vault
VAULT_POD=$(kubectl get pods -n vault -l app=vault -o jsonpath='{.items[0].metadata.name}')

# Проверка статуса инициализации
INIT_STATUS=$(kubectl exec -n vault $VAULT_POD -- vault status -format=json 2>/dev/null | jq -r '.initialized' || echo "false")

if [ "$INIT_STATUS" == "false" ]; then
    echo "Инициализация Vault..."
    
    # Инициализация Vault с 5 ключами, требуется 3 для распечатывания
    INIT_OUTPUT=$(kubectl exec -n vault $VAULT_POD -- vault operator init -key-shares=5 -key-threshold=3 -format=json)
    
    # Сохранение ключей и root token
    echo "$INIT_OUTPUT" > /tmp/vault-init-keys.json
    
    # Извлечение ключей
    UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
    UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]')
    UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]')
    ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
    
    echo "Vault инициализирован!"
    echo ""
    echo "!!! ВАЖНО: Сохраните эти ключи в безопасном месте !!!"
    echo "Root Token: $ROOT_TOKEN"
    echo "Unseal Keys сохранены в /tmp/vault-init-keys.json"
    echo ""
    
    # Распечатывание Vault
    echo "Распечатывание Vault..."
    kubectl exec -n vault $VAULT_POD -- vault operator unseal $UNSEAL_KEY_1
    kubectl exec -n vault $VAULT_POD -- vault operator unseal $UNSEAL_KEY_2
    kubectl exec -n vault $VAULT_POD -- vault operator unseal $UNSEAL_KEY_3
    
    echo "Vault распечатан!"
    
    # Авторизация с root token
    kubectl exec -n vault $VAULT_POD -- vault login $ROOT_TOKEN
    
    # Включение KV secrets engine
    echo "Настройка secrets engine..."
    kubectl exec -n vault $VAULT_POD -- vault secrets enable -path=secret kv-v2
    
    # Создание политик для Node 1
    echo "Создание политики для Node 1..."
    kubectl exec -n vault $VAULT_POD -- sh -c 'cat <<EOF | vault policy write node1-policy -
path "secret/data/node1/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/node1/*" {
  capabilities = ["read", "list"]
}
EOF'

    # Создание политик для Node 2
    echo "Создание политики для Node 2..."
    kubectl exec -n vault $VAULT_POD -- sh -c 'cat <<EOF | vault policy write node2-policy -
path "secret/data/node2/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/node2/*" {
  capabilities = ["read", "list"]
}
EOF'

    # Включение Kubernetes auth method
    echo "Настройка Kubernetes authentication..."
    kubectl exec -n vault $VAULT_POD -- vault auth enable kubernetes
    
    # Конфигурация Kubernetes auth
    kubectl exec -n vault $VAULT_POD -- sh -c 'vault write auth/kubernetes/config \
        kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"'
    
    # Создание ролей для приложений
    echo "Создание роли для приложений Node 1..."
    kubectl exec -n vault $VAULT_POD -- vault write auth/kubernetes/role/node1-app \
        bound_service_account_names=default \
        bound_service_account_namespaces=node1-services \
        policies=node1-policy \
        ttl=24h
    
    echo "Создание роли для приложений Node 2..."
    kubectl exec -n vault $VAULT_POD -- vault write auth/kubernetes/role/node2-app \
        bound_service_account_names=default \
        bound_service_account_namespaces=node2-services \
        policies=node2-policy \
        ttl=24h
    
    # Создание примеров секретов
    echo "Создание примеров секретов..."
    kubectl exec -n vault $VAULT_POD -- vault kv put secret/node1/postgres \
        username=app_user \
        password=SecurePassword123_Node1 \
        host=postgres-node1.node1-services.svc.cluster.local \
        port=5432 \
        database=node1_db
    
    kubectl exec -n vault $VAULT_POD -- vault kv put secret/node2/postgres \
        username=app_user \
        password=SecurePassword456_Node2 \
        host=postgres-node2.node2-services.svc.cluster.local \
        port=5432 \
        database=node2_db
    
    echo ""
    echo "=== Vault настроен успешно! ==="
    echo ""
    echo "Для доступа к UI: http://localhost:30820"
    echo "Root Token: $ROOT_TOKEN"
    echo ""
    echo "Примеры использования:"
    echo "  kubectl exec -n vault $VAULT_POD -- vault kv get secret/node1/postgres"
    echo "  kubectl exec -n vault $VAULT_POD -- vault kv get secret/node2/postgres"
    
else
    echo "Vault уже инициализирован"
    
    # Проверка sealed статуса
    SEALED=$(kubectl exec -n vault $VAULT_POD -- vault status -format=json 2>/dev/null | jq -r '.sealed')
    
    if [ "$SEALED" == "true" ]; then
        echo "Vault запечатан. Требуется распечатывание вручную."
        echo "Используйте: kubectl exec -n vault $VAULT_POD -- vault operator unseal <KEY>"
    else
        echo "Vault готов к работе"
    fi
fi
