# IaC + CI/CD демо для сервиса объявлений

Этот пакет содержит примеры файлов для выполнения ДЗ: Terraform-инфраструктура, Ansible-плейбуки, Dockerfile, манифесты Kubernetes и GitHub Actions для пайплайна.

## Архитектурный контекст
Сервис — микросервисная система с синхронными REST/gRPC-вызовами и асинхронным обменом событиями через Kafka. Для пользовательских обновлений — WebSocket/SSE. (см. подробности в ваших документах).

## Что внутри
```
terraform/                      # VPC, подсети, SG, EC2 для app и db, S3-бакет
ansible/
  inventory.ini                 # инвентарь: подставьте публичные IP
  playbook.yml                  # роли: docker, db(Postgres), app (compose)
  roles/
    docker/tasks/main.yml
    db/tasks/main.yml
    app/tasks/main.yml
k8s/
  deployment-service-ingress.yaml
app/
  app.py, requirements.txt, tests/
Dockerfile
.github/workflows/ci-cd.yml     # GitHub Actions: build -> test -> push -> deploy -> Telegram
```

## Диаграмма пайплайна (Mermaid)
```mermaid
flowchart LR
  A[Push/PR] --> B[Build Docker]
  B --> C[Tests]
  C -->|ok| D[Push to GHCR]
  D --> E[Deploy to K8s]
  E --> F[(Ingress/Service)]
  C -->|fail| T[Telegram Notify]
  E --> T
```

## Быстрый старт

### 1) Terraform (AWS пример)
1. Установите `terraform` и создайте ключ:
   ```bash
   export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
   cd terraform
   terraform init
   terraform apply -auto-approve
   ```
2. Запомните вывод `app_public_ip` и `db_public_ip`.

### 2) Ansible
1. Установите Ansible и коллекцию docker:
   ```bash
   ansible-galaxy collection install community.docker
   ```
2. Отредактируйте `ansible/inventory.ini` — замените `APP_PUBLIC_IP` и `DB_PUBLIC_IP`.
3. Запустите плейбук:
   ```bash
   cd ansible
   ansible-playbook -i inventory.ini playbook.yml
   ```
   Это установит Docker, поднимет Postgres и развернёт приложение в контейнере.

### 3) Сборка и контейнер
Локально:
```bash
docker build -t ads-demo:dev .
docker run --rm -p 8000:8000 -e DATABASE_URL="postgresql://ads:change_me@localhost:5432/adsdb" ads-demo:dev
```

### 4) Kubernetes
Подготовьте кластер, NGINX Ingress и секрет pull (если частный реестр). Затем примените манифесты:
```bash
kubectl apply -f k8s/deployment-service-ingress.yaml
```

### 5) CI/CD (GitHub Actions)
Добавьте секреты репозитория:
- `KUBECONFIG_B64` — kubeconfig, закодированный в base64
- `TG_BOT_TOKEN`, `TG_CHAT_ID` — для телеграм-уведомлений

При пуше в `main` произойдёт: build→tests→push to GHCR→deploy→уведомление.

## Примечания
- Все значения `OWNER`, `change_me`, домены — замените под вашу среду.
- Для S3-совместимого MinIO можно использовать `aws_s3_bucket` с кастомным endpoint через провайдер AWS (env `AWS_ENDPOINT_URL`).