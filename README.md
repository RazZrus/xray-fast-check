# xray-deploy

Скрипты для быстрого развёртывания Xray + Hysteria2 на VPS. Удобно для тестирования на пробных периодах.

## Что устанавливается

| Протокол | Порт | Транспорт |
|----------|------|-----------|
| VLESS + REALITY | 443/TCP | XHTTP |
| VLESS + REALITY | 2053/TCP | gRPC |
| Hysteria2 | 8443/UDP | QUIC |

Всё генерируется автоматически: UUID, REALITY keypair, сертификат для Hysteria2.

## Требования

- Ubuntu 22.04 / 24.04 или Debian 11/12
- Root доступ
- Чистый сервер (не занят порт 443)

## Установка

Подключиться к серверу и выполнить:

```bash
bash <(curl -sL https://raw.githubusercontent.com/xray-fast-check/xray-deploy/main/deploy.sh)
```

Или скопировать скрипт вручную:

```bash
scp deploy.sh root@SERVER_IP:/root/
ssh root@SERVER_IP
bash deploy.sh
```

По завершении скрипт выведет три готовые ссылки для клиентов.

## Удаление

```bash
bash <(curl -sL https://raw.githubusercontent.com/xray-fast-check/xray-deploy/main/uninstall.sh)
```

Или если уже на сервере:

```bash
bash uninstall.sh
```

Удаляет Xray, Hysteria2, все конфиги и правила файрвола.

## Клиенты

Поддерживаемые приложения:

- **Android:** Hiddify, v2rayNG, NekoBox
- **iOS:** Hiddify, Streisand, FoXray
- **Windows:** v2rayN
- **macOS:** FoXray, V2RayXS

## Файлы

| Файл | Описание |
|------|----------|
| `deploy.sh` | Установка Xray + Hysteria2, вывод ссылок |
| `uninstall.sh` | Полное удаление |
