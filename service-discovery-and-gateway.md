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
