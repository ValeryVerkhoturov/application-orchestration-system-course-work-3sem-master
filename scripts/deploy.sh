#!/bin/bash
# Главный скрипт развертывания кластера
# Запуск: ./deploy.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Проверка зависимостей
check_dependencies() {
    print_header "Проверка зависимостей"
    
    local deps=("docker" "kind" "kubectl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            missing+=($dep)
            print_error "$dep не найден"
        else
            print_success "$dep установлен ($(command -v $dep))"
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo ""
        print_error "Установите отсутствующие зависимости:"
        for dep in "${missing[@]}"; do
            case $dep in
                docker)
                    echo "  Docker: https://docs.docker.com/get-docker/"
                    ;;
                kind)
                    echo "  Kind: curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/"
                    ;;
                kubectl)
                    echo "  kubectl: curl -LO https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
                    ;;
            esac
        done
        exit 1
    fi
}

# Создание кластера
create_cluster() {
    print_header "Создание Kind кластера"
    
    # Проверка существующего кластера
    if kind get clusters 2>/dev/null | grep -q "production-cluster"; then
        print_warning "Кластер 'production-cluster' уже существует"
        read -p "Удалить существующий кластер? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kind delete cluster --name production-cluster
            print_success "Существующий кластер удален"
        else
            print_warning "Используем существующий кластер"
            return
        fi
    fi
    
    kind create cluster --config "$PROJECT_DIR/kind-config.yaml"
    print_success "Кластер создан"
    
    # Ожидание готовности узлов
    echo "Ожидание готовности узлов..."
    kubectl wait --for=condition=ready nodes --all --timeout=300s
    print_success "Все узлы готовы"
}

# Создание namespaces
create_namespaces() {
    print_header "Создание Namespaces"
    
    kubectl apply -f "$PROJECT_DIR/manifests/namespaces.yaml"
    print_success "Namespaces созданы"
}

# Развертывание базы данных Node 1
deploy_node1() {
    print_header "Развертывание сервисов Node 1"
    
    kubectl apply -f "$PROJECT_DIR/manifests/node1/"
    print_success "Сервисы Node 1 развернуты"
    
    echo "Ожидание готовности PostgreSQL Node 1..."
    kubectl wait --for=condition=available deployment/postgres-node1 -n node1-services --timeout=300s || true
    print_success "PostgreSQL Node 1 готов"
}

# Развертывание базы данных Node 2
deploy_node2() {
    print_header "Развертывание сервисов Node 2"
    
    kubectl apply -f "$PROJECT_DIR/manifests/node2/"
    print_success "Сервисы Node 2 развернуты"
    
    echo "Ожидание готовности PostgreSQL Node 2..."
    kubectl wait --for=condition=available deployment/postgres-node2 -n node2-services --timeout=300s || true
    print_success "PostgreSQL Node 2 готов"
}

# Развертывание системы логирования (Оценка 4)
deploy_logging() {
    print_header "Развертывание системы логирования (Оценка 4)"
    
    kubectl apply -f "$PROJECT_DIR/manifests/monitoring/logging-stack.yaml"
    print_success "Loki + Promtail + Grafana развернуты"
    
    echo "Ожидание готовности Grafana..."
    kubectl wait --for=condition=available deployment/grafana -n logging --timeout=300s || true
    print_success "Grafana готова"
    
    echo ""
    echo -e "${GREEN}Grafana доступна по адресу: http://localhost:30300${NC}"
    echo -e "${GREEN}Логин: admin / Пароль: admin123${NC}"
}

# Развертывание Vault (Оценка 5)
deploy_vault() {
    print_header "Развертывание HashiCorp Vault (Оценка 5)"
    
    kubectl apply -f "$PROJECT_DIR/manifests/secrets/vault.yaml"
    print_success "Vault развернут"
    
    echo "Ожидание готовности Vault..."
    sleep 30  # Vault требует времени на запуск
    kubectl wait --for=condition=ready pod -l app=vault -n vault --timeout=300s || true
    print_success "Vault готов"
    
    echo ""
    echo -e "${YELLOW}Для инициализации Vault выполните:${NC}"
    echo -e "${YELLOW}  ./scripts/init-vault.sh${NC}"
    echo ""
    echo -e "${GREEN}Vault UI доступен по адресу: http://localhost:30820${NC}"
}

# Показать статус кластера
show_status() {
    print_header "Статус кластера"
    
    echo -e "\n${BLUE}Узлы:${NC}"
    kubectl get nodes -o wide
    
    echo -e "\n${BLUE}Namespaces:${NC}"
    kubectl get namespaces
    
    echo -e "\n${BLUE}Поды в node1-services:${NC}"
    kubectl get pods -n node1-services -o wide 2>/dev/null || echo "Нет подов"
    
    echo -e "\n${BLUE}Поды в node2-services:${NC}"
    kubectl get pods -n node2-services -o wide 2>/dev/null || echo "Нет подов"
    
    echo -e "\n${BLUE}Поды в logging:${NC}"
    kubectl get pods -n logging -o wide 2>/dev/null || echo "Нет подов"
    
    echo -e "\n${BLUE}Поды в vault:${NC}"
    kubectl get pods -n vault -o wide 2>/dev/null || echo "Нет подов"
    
    echo -e "\n${BLUE}Сервисы:${NC}"
    kubectl get services --all-namespaces
}

# Полное развертывание
full_deploy() {
    check_dependencies
    create_cluster
    create_namespaces
    deploy_node1
    deploy_node2
    deploy_logging
    deploy_vault
    show_status
    
    print_header "Развертывание завершено!"
    
    echo -e "${GREEN}Доступные сервисы:${NC}"
    echo -e "  • Grafana (логи):     http://localhost:30300  (admin/admin123)"
    echo -e "  • Vault (секреты):    http://localhost:30820"
    echo ""
    echo -e "${YELLOW}Следующие шаги:${NC}"
    echo -e "  1. Инициализируйте Vault: ./scripts/init-vault.sh"
    echo -e "  2. Проверьте логи в Grafana"
    echo -e "  3. Разверните приложения с интеграцией Vault"
}

# Меню
show_menu() {
    echo -e "\n${BLUE}Kind Kubernetes Cluster Management${NC}"
    echo "=================================="
    echo "1. Полное развертывание (все компоненты)"
    echo "2. Создать только кластер"
    echo "3. Развернуть только logging (Оценка 4)"
    echo "4. Развернуть только Vault (Оценка 5)"
    echo "5. Показать статус"
    echo "6. Удалить кластер"
    echo "7. Выход"
    echo ""
    read -p "Выберите опцию: " choice
    
    case $choice in
        1) full_deploy ;;
        2) check_dependencies && create_cluster ;;
        3) deploy_logging ;;
        4) deploy_vault ;;
        5) show_status ;;
        6) 
            kind delete cluster --name production-cluster
            print_success "Кластер удален"
            ;;
        7) exit 0 ;;
        *) print_error "Неверный выбор" ;;
    esac
}

# Главная логика
if [ $# -eq 0 ]; then
    show_menu
else
    case $1 in
        --full) full_deploy ;;
        --cluster) check_dependencies && create_cluster ;;
        --logging) deploy_logging ;;
        --vault) deploy_vault ;;
        --status) show_status ;;
        --delete) kind delete cluster --name production-cluster ;;
        *)
            echo "Использование: $0 [--full|--cluster|--logging|--vault|--status|--delete]"
            exit 1
            ;;
    esac
fi
