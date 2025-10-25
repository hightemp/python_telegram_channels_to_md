# python_telegram_channels_to_md

Здесь находятся репозиторий с скаченными telegram каналами в markdown + скрипт-сервис на python.

```console
$ make
Доступные цели:
  make init               - создать venv, установить зависимости, скопировать config.yaml если отсутствует
  make run                - запустить экспорт каналов
  make clean              - удалить артефакты (кэш .pyc, __pycache__)
  make purge              - полная очистка: clean + удаление .venv
  make config             - создать config.yaml из примера, если его нет
  make install-systemd    - установить systemd юниты и запустить таймер (SCOPE=user|system, TIMER_CALENDAR='daily' или '*-*-* 03:00')
  make uninstall-systemd  - остановить и удалить systemd юниты
  make systemd-status     - показать статус таймера и сервиса
  make systemd-run-once   - однократно запустить сервис вручную
```

## Установка

```console
python -m venv .venv
. .venv/bin/activate   
# Windows: .venv\Scripts\activate
pip install telethon pyyaml
python download_channels.py
```