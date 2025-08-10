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