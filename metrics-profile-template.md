**Сбор метрик по уровням:**
#### 1. Инфраструктура:
- Загрузка CPU/Memory/IO
- Время отклика сервисов
- Количество доступных подов в k8s (по каждому сервису)
	- **kube-state-metrics**: `kube_deployment_status_replicas_available`, `kube_pod_container_status_restarts_total`
	- Node exporter/cAdvisor: CPU/Memory/IO, throttling `container_cpu_cfs_throttled_seconds_total`.
- Количество рестартов подов
- Доступность PostgreSQL, Redis, Kafka (через blackbox-exporter)
#### 2. Приложение:
- **Latency**: p50/p95/p99 для внешних REST и внутренних gRPC.
- **Throughput**: RPS/eps (events per second).
- **Error rate**: доля 5xx/4xx по REST, **grpc_status != OK** по gRPC.
- **Saturation**: расход CPU/RAM, количество активных коннектов WS, пул соединений к БД/кэшам.
- **Queueing**: Kafka lag, глубина outbox, время “событие→обработано”
##### API Gateway (Kongo)
- RPS по роутам, p95/p99 latency, 4xx/5xx rate.
- TLS рукопожатия, открытые коннекты, upstream failures.
- Для Kong: `kong_http_requests_total`, `kong_latency_*`
##### REST & gRPC
- **REST** (Spring): `http_server_requests_seconds_*`, `http_server_requests_seconds_count`, `http_server_requests_seconds_sum` (Micrometer)
- **gRPC**: `grpc_server_started_total`, `grpc_server_handled_total{code!=OK}`, `grpc_server_handling_seconds_bucket` (grpc‑java + Micrometer)
- Ретраи/таймауты: счётчики срабатываний (resilience4j: `resilience4j_circuitbreaker_*`, `resilience4j_retry_*`)
##### WebSockets
- Активные соединения (всего/на инстанс), подключений/сек, отвалов/сек.
- Средний размер сообщения, outbound msgs/sec, drop/overflow.
- Ping/pong latency, время подписки/авторизации.
##### Kafka & Outbox
- **Broker**: `kafka_server_brokertopicmetrics_messagesin_total`, `kafka_controller_kafkacontroller_activecontrollercount`, ISR, under‑replicated partitions.
- **Consumer**: количество лаков на group/partition (`kafka_consumergroup_lag` из Kafka Exporter), rebalance count, processing latency (кастом: разница `processed_at - produced_at`).
- **Producer**: `record-error-rate`, `record-retry-rate` (JMX).
- **Outbox**: размер очереди, возраст старейшей записи, скорость удаления (`outbox_pending`, `outbox_oldest_age_seconds`, `outbox_drain_rate`).
#### 3. База данных:
**PostgreSQL**
- Подключения (active/idle), блокировки, **время запросов p95/p99**.
- **Replication lag** (отставание реплик), скорость WAL, частота чекпоинтов.
- Hit ratio буферов, «тяжёлые» запросы (`pg_stat_statements`), рост таблиц/индексов, фрагментация.

**Redis**
- **Hit rate**, латентность команд, использование памяти.
- Кол-во ключей, **evictions**, пропускная способность.
- Состояние репликации/кластера, персистентность (RDB/AOF).

**Kafka**
- Скорость публикации/потребления на топик/партицию.
- **Отставание потребителей (consumer lag)**.
- **Under-replicated partitions**, размер ISR, ошибки продюсеров/консьюмеров.
- Нагруженность дисков и сеть брокеров.

**Elasticsearch**
- Состояние кластера (green/yellow/red), **latency поиска/indexing**.
- Нагрузка на heap/GC, размер шардов/сегментов.
- Скорость индексирования, ошибки отказа запросов.

**CDN**
- **Cache hit ratio**, количество обращений к origin.
- TTFB, трафик по регионам, доля 4xx/5xx.
- Количество инвалидаций/пуржей, ошибки загрузки.
###  Инструменты мониторинга
- **Prometheus** — сбор и агрегация метрик со всех сервисов и экспортёров.
- **Grafana** — визуализация дашбордов с метриками (инфраструктура, приложения, Kafka, Redis, PostgreSQL).
- **Alertmanager** — оповещение по метрикам (падения, перегрузки, ошибки).
- **Loki** / **ELK (Elasticsearch, Logstash, Kibana)** — для логов и текстовой диагностики.
- **Jaeger** — для распределённой трассировки запросов между микросервисами.
- **Blackbox exporter** — проверка доступности внешних зависимостей (платёжки, API доставки).
- **Kafka Exporter** — статус брокеров, лаги консьюмеров, offset drift.
	- **JMX Exporter** для Kafka брокеров и Java сервисов.
### Шаблон профиля производительности

| Компонент      | Метрика                 | Целевое значение | Инструмент           | Назначение / Интерпретация                     |
| -------------- | ----------------------- | ---------------- | -------------------- | ---------------------------------------------- |
| API Gateway    | RPS                     | > 1000           | Prometheus + Grafana | Общее количество запросов в секунду            |
| API Gateway    | p95 latency             | < 300ms          | Prometheus           | Время ответа на 95% запросов                   |
| Redis          | Cache hit ratio         | > 85%            | Redis Exporter       | Эффективность кэша (низкий — перегрузка БД)    |
| PostgreSQL     | Average query time      | < 100ms          | Postgres Exporter    | Среднее время SQL-запроса                      |
| PostgreSQL     | Replication lag         | < 1s             | Postgres Exporter    | Задержка репликации, влияет на консистентность |
| Kafka          | Consumer group lag      | < 1000           | Kafka Exporter       | Отставание потребителей                        |
| Kafka          | Broker availability     | 100%             | Kafka Exporter       | Здоровье кластера Kafka                        |
| Order Service  | Error rate (5xx)        | < 1%             | Prometheus           | Надёжность API                                 |
| Search Service | Fulltext query duration | < 500ms          | Prometheus / APM     | Быстродействие поиска                          |
### Сценарий анализа метрик и диагностики проблем

**Сценарий: Повышенная задержка в оформлении заказа**

1. **Оповещение**:
   - Alert от Prometheus: "p95 latency of OrderService > 1.2s"

2. **Первичный анализ в Grafana**:
   - Смотрим: RPS, ошибки 5xx, рост задержек.
   - Анализируем нагрузку на OrderService (CPU/Memory/Количество подов).

3. **Проверка Kafka**:
   - Смотрим на лаги в очередях и задержка в обработке событий
   - Есть ли недоставленные сообщения (dead-letter queue)?

4. **Redis**:
   - Cache miss rate вырос? Много промахов и запросов к БД?

5. **PostgreSQL**:
   - Увеличилась ли нагрузка (время выполнения запросов)?
   - Есть ли блокировки или долгие транзакции?
   - Проверяем индексы — не ушли ли запросы в full scan.

6. **Jaeger (tracing)**:
   - Строим трассировку цепочки запросов клиента через все микросервисы.
   - Ищем, где именно возникла задержка — API Gateway? OrderService? вызов Payment API?

7. **Решения:**
   - Если перегружен сервис — масштабируем.
   - Если кэш неэффективен — пересматриваем TTL и алгоритм прогрева.
   - Если проблемы в БД — пересматриваем индексацию или рефакторим запросы.
   - Если проблемы с Kafka — перераспределение партиций или оптимизация потребителей.
