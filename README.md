# Kubernetes кластер с Kind

## Описание решения

Данное решение создает вычислительный кластер из 3 узлов с использованием Kind (Kubernetes in Docker):
- **1 Master** (control-plane) - управляющий узел
- **2 Worker** - рабочие узлы для размещения сервисов

## Архитектура кластера

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PRODUCTION CLUSTER                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        MASTER NODE                                    │   │
│  │                    (Control Plane)                                    │   │
│  │                                                                       │   │
│  │  • Kubernetes API Server                                              │   │
│  │  • etcd (cluster state)                                               │   │
│  │  • Controller Manager                                                 │   │
│  │  • Scheduler                                                          │   │
│  │  • Политика: автовосстановление через N попыток                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                   │                                          │
│                    ┌──────────────┴──────────────┐                          │
│                    │                             │                          │
│  ┌─────────────────▼──────────────┐ ┌──────────▼─────────────────────────┐ │
│  │         WORKER NODE 1          │ │         WORKER NODE 2              │ │
│  │      (node1-services)          │ │      (node2-services)              │ │
│  │      http://localhost:30501    │ │      http://localhost:30502        │ │
│  │                                │ │                                    │ │
│  │  ┌──────────────────────────┐  │ │  ┌──────────────────────────┐     │ │
│  │  │     PostgreSQL DB        │  │ │  │     PostgreSQL DB        │     │ │
│  │  │   (Единый слой данных)   │  │ │  │   (Единый слой данных)   │     │ │
│  │  │   Strategy: Recreate     │  │ │  │   Strategy: Recreate     │     │ │
│  │  │   Tables: items,         │  │ │  │   Tables: orders,        │     │ │
│  │  │           health_checks  │  │ │  │           audit_log      │     │ │
│  │  └──────────────────────────┘  │ │  └──────────────────────────┘     │ │
│  │              │                 │ │              │                     │ │
│  │  ┌──────────▼───────────────┐  │ │  ┌──────────▼───────────────┐     │ │
│  │  │   Python Flask App       │  │ │  │   Python Flask App       │     │ │
│  │  │   (Items Service)        │  │ │  │   (Orders Service)       │     │ │
│  │  │  • Flask + Gunicorn      │  │ │  │  • Flask + Gunicorn      │     │ │
│  │  │  • psycopg2 → PostgreSQL │  │ │  │  • psycopg2 → PostgreSQL │     │ │
│  │  │  • failureThreshold: 3   │  │ │  │  • failureThreshold: 3   │     │ │
│  │  │  • restartPolicy: Always │  │ │  │  • restartPolicy: Always │     │ │
│  │  │  • 2 replicas            │  │ │  │  • 2 replicas            │     │ │
│  │  └──────────────────────────┘  │ │  └──────────────────────────┘     │ │
│  │                                │ │                                    │ │
│  │  Автовосстановление: N=3      │ │  Автовосстановление: N=3          │ │
│  └────────────────────────────────┘ └────────────────────────────────────┘ │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                           INFRASTRUCTURE SERVICES                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                    LOGGING (Оценка 4)                                   ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────────┐ ││
│  │  │   Promtail  │─▶│    Loki     │──│         Grafana                 │ ││
│  │  │  (DaemonSet)│  │  (Storage)  │  │  (Visualization)                │ ││
│  │  │  На каждом  │  │             │  │  http://localhost:30300         │ ││
│  │  │    узле     │  │             │  │  admin/admin123                 │ ││
│  │  └─────────────┘  └─────────────┘  └─────────────────────────────────┘ ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                    VAULT (Оценка 5)                                     ││
│  │  ┌───────────────────────────────────────────────────────────────────┐ ││
│  │  │                  HashiCorp Vault                                   │ ││
│  │  │              (Secrets Management)                                  │ ││
│  │  │                                                                    │ ││
│  │  │  ┌─────────────────┐    ┌─────────────────┐                       │ ││
│  │  │  │ secret/node1/*  │    │ secret/node2/*  │                       │ ││
│  │  │  │  - postgres     │    │  - postgres     │                       │ ││
│  │  │  │  credentials    │    │  credentials    │                       │ ││
│  │  │  └────────┬────────┘    └────────┬────────┘                       │ ││
│  │  │           │                      │                                 │ ││
│  │  │           ▼                      ▼                                 │ ││
│  │  │  ┌─────────────────────────────────────────────────────────────┐  │ ││
│  │  │  │         Kubernetes Authentication                           │  │ ││
│  │  │  │  • node1-app role → node1-services namespace               │  │ ││
│  │  │  │  • node2-app role → node2-services namespace               │  │ ││
│  │  │  └─────────────────────────────────────────────────────────────┘  │ ││
│  │  │                                                                    │ ││
│  │  │  http://localhost:30820                                           │ ││
│  │  └───────────────────────────────────────────────────────────────────┘ ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Политики отказоустойчивости

### Автовосстановление через N попыток

Реализовано через Kubernetes механизмы:

1. **restartPolicy: Always** - контейнер автоматически перезапускается при сбое
2. **livenessProbe с failureThreshold: 3** - N=3 неудачных проверок до перезапуска
3. **Kubelet автоматически** перезапускает контейнеры при сбоях

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 80
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3  # N=3 попытки
```

## Стратегия обновления сервисов

**Требования:**
- ✅ Допускается простой сервиса
- ✅ Без смешивания версий  
- ✅ Без отката в случае сбоя при обновлении

**Решение: Strategy: Recreate**

```yaml
spec:
  strategy:
    type: Recreate
```

Эта стратегия:
1. Останавливает все старые поды
2. Запускает новые поды
3. Не поддерживает автоматический rollback
4. Гарантирует отсутствие смешивания версий

## Структура проекта

```
k8s-cluster/
├── kind-config.yaml              # Конфигурация Kind кластера
├── manifests/
│   ├── namespaces.yaml           # Определения namespace
│   ├── node1/
│   │   └── database.yaml         # PostgreSQL + сервисы для Node 1
│   ├── node2/
│   │   └── database.yaml         # PostgreSQL + сервисы для Node 2
│   ├── monitoring/
│   │   └── logging-stack.yaml    # Loki + Promtail + Grafana
│   └── secrets/
│       ├── vault.yaml            # HashiCorp Vault
│       └── vault-app-example.yaml # Пример интеграции с Vault
└── scripts/
    ├── deploy.sh                 # Главный скрипт развертывания
    └── init-vault.sh             # Инициализация Vault
```

## Установка и запуск

### Предварительные требования

```bash
# Docker
curl -fsSL https://get.docker.com | sh

# Kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/

# kubectl
curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### Развертывание

```bash
# Полное развертывание
cd k8s-cluster
chmod +x scripts/*.sh
./scripts/deploy.sh --full

# Или интерактивно
./scripts/deploy.sh
```

### Инициализация Vault

```bash
./scripts/init-vault.sh
```

Сохраните Root Token и Unseal Keys!

## Доступ к сервисам

| Сервис | URL | Credentials |
|--------|-----|-------------|
| Python App Node 1 | http://localhost:30501 | - |
| Python App Node 2 | http://localhost:30502 | - |
| Grafana | http://localhost:30300 | admin / admin123 |
| Vault UI | http://localhost:30820 | Root Token |

## API Endpoints

### Node 1 - Items Service (http://localhost:30501)

| Метод | Endpoint | Описание |
|-------|----------|----------|
| GET | `/` | Информация о сервисе |
| GET | `/health` | Health check с проверкой БД |
| GET | `/ready` | Readiness check |
| GET | `/items` | Получить все items |
| POST | `/items` | Создать item `{"name": "...", "description": "..."}` |
| DELETE | `/items/{id}` | Удалить item |
| GET | `/db/stats` | Статистика БД |

### Node 2 - Orders Service (http://localhost:30502)

| Метод | Endpoint | Описание |
|-------|----------|----------|
| GET | `/` | Информация о сервисе |
| GET | `/health` | Health check с проверкой БД |
| GET | `/ready` | Readiness check |
| GET | `/orders` | Получить все заказы |
| POST | `/orders` | Создать заказ `{"product_name": "...", "quantity": 1, "price": 10.99}` |
| PUT | `/orders/{id}` | Обновить статус `{"status": "completed"}` |
| DELETE | `/orders/{id}` | Удалить заказ |
| GET | `/audit` | Лог действий |
| GET | `/db/stats` | Статистика БД |

### Примеры использования API

```bash
# Node 1 - создать item
curl -X POST http://localhost:30501/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Item", "description": "Test description"}'

# Node 1 - получить все items
curl http://localhost:30501/items

# Node 2 - создать заказ
curl -X POST http://localhost:30502/orders \
  -H "Content-Type: application/json" \
  -d '{"product_name": "Laptop", "quantity": 2, "price": 999.99}'

# Node 2 - обновить статус заказа
curl -X PUT http://localhost:30502/orders/1 \
  -H "Content-Type: application/json" \
  -d '{"status": "shipped"}'

# Проверить health
curl http://localhost:30501/health
curl http://localhost:30502/health
```

## Работа с Vault

### Получение секретов

```bash
# Получить секреты PostgreSQL для Node 1
kubectl exec -n vault $(kubectl get pods -n vault -l app=vault -o jsonpath='{.items[0].metadata.name}') -- vault kv get secret/node1/postgres

# Получить секреты PostgreSQL для Node 2
kubectl exec -n vault $(kubectl get pods -n vault -l app=vault -o jsonpath='{.items[0].metadata.name}') -- vault kv get secret/node2/postgres
```

### Добавление нового секрета

```bash
kubectl exec -n vault <vault-pod> -- vault kv put secret/node1/app-secret \
    api_key=my-secret-key \
    api_url=https://api.example.com
```

## Просмотр логов

### Через Grafana

1. Откройте http://localhost:30300
2. Войдите (admin/admin123)
3. Перейдите в Explore → выберите Loki
4. Используйте запросы:
   - `{namespace="node1-services"}` - логи Node 1
   - `{namespace="node2-services"}` - логи Node 2
   - `{app="postgres"}` - логи PostgreSQL

### Через kubectl

```bash
# Логи PostgreSQL Node 1
kubectl logs -n node1-services -l app=postgres -f

# Логи приложения Node 2
kubectl logs -n node2-services -l app=app-service -f
```

## Мониторинг состояния

```bash
# Статус узлов
kubectl get nodes -o wide

# Все поды
kubectl get pods --all-namespaces -o wide

# События
kubectl get events --all-namespaces --sort-by='.metadata.creationTimestamp'
```

## Тестирование отказоустойчивости

### Тест автовосстановления

```bash
# Убить под PostgreSQL
kubectl delete pod -n node1-services -l app=postgres

# Наблюдать за восстановлением
kubectl get pods -n node1-services -w
```

### Тест обновления (Recreate)

```bash
# Изменить версию образа
kubectl set image deployment/postgres-node1 postgres=postgres:16-alpine -n node1-services

# Наблюдать за обновлением
kubectl rollout status deployment/postgres-node1 -n node1-services
```

## Удаление кластера

```bash
./scripts/deploy.sh --delete
# или
kind delete cluster --name production-cluster
```

## Соответствие требованиям

| Требование | Реализация | Статус |
|------------|------------|--------|
| 3 узла (1 master + 2 worker) | Kind cluster config | ✅ |
| Автовосстановление master | restartPolicy + livenessProbe | ✅ |
| Автовосстановление worker 1 | failureThreshold: 3 | ✅ |
| Автовосстановление worker 2 | failureThreshold: 3 | ✅ |
| Стратегия: простой допускается | Strategy: Recreate | ✅ |
| Стратегия: без смешивания версий | Strategy: Recreate | ✅ |
| Стратегия: без отката | Recreate (no rollback) | ✅ |
| Node 1: единый слой данных (БД) | PostgreSQL | ✅ |
| Node 2: единый слой данных (БД) | PostgreSQL | ✅ |
| Оценка 4: Централизованные логи | Loki + Promtail + Grafana | ✅ |
| Оценка 5: Сервер секретов | HashiCorp Vault | ✅ |
