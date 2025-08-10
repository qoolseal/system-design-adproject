## Service Discovery
### Kubernetes
- используем функционал k8s: каждый микросервис развёрнут как Deployment + Service (ClusterIP)
- Kubernetes поддерживает DNS‑имена вида:  `http://user-service:8080`.
- kube‑proxy перенаправляет трафик на один из доступных подов по round-robin. поды, у которых `readinessProbe` не пройдена, в балансировку не попадают.
### Настройка
1. Разворачиваем микросервисы через Deployment
   - задаём readinessProbe и livenessProbe
   - например, для order-service:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
    spec:
      containers:
        - name: order-service
          image: registry.example.com/order-service:1.0.0
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
```

2. Создаём ClusterIP Service
   - для каждого из микросервисов будет свой Service
   - например, для order-service:
   - Kubernetes автоматически создаёт DNS-запись для имени `order-service`.
```yaml
apiVersion: v1
kind: Service
metadata:
  name: order-service
spec:
  type: ClusterIP
  selector:
    app: order-service
  ports:
    - name: http
      port: 8080        # порт, по которому клиенты будут обращаться в кластере
      targetPort: 8080  # порт внутри контейнера
```

3. Автоматическое обнаружение работает:
   - после запуска подов утилита кубера регистрирует их в API-сервере
   - Service (k8s) создаёт объект Endpoints и хранит в нём список ip-адресов подов
   - автоматически создаётся DNS-имя для сервиса
   - клиент обращается по общему имени, то есть по виртуальному IP внутри кластера
   - kube-proxy перенаправляет трафик на один из доступных подов
### Распространяется на микросервисы:
|Сервис|Протоколы внутри кластера|Для кого нужен DNS-доступ|
|---|---|---|
|**order-service**|gRPC, REST|API Gateway, payment-service, delivery-service, notification-service|
|**payment-service**|gRPC|order-service|
|**delivery-service**|gRPC|order-service|
|**user-service**|REST|API Gateway, ad-service, search-service|
|**ad-service**|REST|API Gateway, search-service|
|**search-service**|REST|API Gateway, ad-service|
|**media-service**|REST|API Gateway|
|**notification-service**|gRPC (внутренний API)|order-service, payment-service, delivery-service|
|**report-service**|REST|API Gateway|
## API Gateway - Kong
### Цели API Gateway
- **Маршрутизация**: внешние запросы по HTTP/2 или HTTP/3 -> в конкретный микросервис по пути и методу.
- **Аутентификация**: валидация JWT (OAuth2/OIDC), проверка прав (scopes/roles).
- **Rate Limiting**: ограничение числа запросов для защиты от DDoS/злоупотреблений.
- **Обогащение запросов**: проброс `X-Request-ID` и `traceparent` для трассировки.
- **TLS Termination**: шифрование между клиентом и шлюзом, опционально mTLS для доверенных партнёров.
### Правила маршрутизации
- Задаём маршрутизацию по префиксу, например api/v1/orders -> order-service
```yaml
_format_version: "3.0"
services:
  - name: order-service
    url: http://order-service:8080
    routes:
      - name: orders
        paths: [ "/api/v1/orders", "/api/v1/orders/*" ]
        methods: [ GET, POST, PATCH, PUT, DELETE ]
  - name: user-service
    url: http://user-service:8080
    routes:
      - name: users
        paths: [ "/api/v1/users", "/api/v1/users/*" ]
        methods: [ GET, POST, PATCH, DELETE ]
  - name: search-service
    url: http://search-service:8080
    routes:
      - name: search
        paths: [ "/api/v1/search" ]
        methods: [ GET ]
  - name: notification-service
    url: http://notification-service:8080
    routes:
      - name: notifications
        paths: [ "/api/v1/notifications/*" ]
        methods: [ GET, POST ]
```
### Аутентификация
- Подключаем проверку JWT ко всем сервисам, кроме публичных (например, `/health`).
- Валидация по публичному ключу OIDC-провайдера (Auth0, Keycloak).
- Используем `scope` для ограничения доступа к API:
    - `orders:read` для GET `/orders`
    - `orders:write` для POST/PATCH/DELETE `/orders`
### Ограничения запросов
- Лимит на пользователя (`consumer_id` из JWT).
- Для публичных API можно ставить более жёсткие лимиты.
- например:
```yaml
plugins:
  - name: rate-limiting
    service: order-service
    config:
      minute: 120        # до 120 запросов в минуту
      policy: local      # хранение счётчика локально
```