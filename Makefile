SHELL := /bin/bash

VENV_DIR := .venv
PY := $(VENV_DIR)/bin/python
PIP := $(VENV_DIR)/bin/pip

PROJECT := python_telegram_channels_to_md

# Systemd/unit vars
REPO_DIR := $(shell pwd)
UNIT_NAME := telegram-channels-to-md
SERVICE_SRC := systemd/$(UNIT_NAME).service.in
TIMER_SRC := systemd/$(UNIT_NAME).timer.in

# Installation params
SCOPE ?= user              # user|system
TIMER_CALENDAR ?= daily    # e.g. daily or "*-*-* 03:00"

ifeq ($(SCOPE),user)
  UNIT_DIR := $(HOME)/.config/systemd/user
  SYSTEMCTL := systemctl --user
else
  UNIT_DIR := /etc/systemd/system
  SYSTEMCTL := sudo systemctl
endif

# Run-as params for system scope
RUN_AS_USER ?= $(shell id -un)
RUN_AS_HOME ?= $(shell getent passwd $(RUN_AS_USER) | cut -d: -f6)

.DEFAULT_GOAL := help

.PHONY: help init venv install run config clean purge install-systemd uninstall-systemd systemd-status systemd-run-once

help:
	@echo "Доступные цели:"
	@echo "  make init               - создать venv, установить зависимости, скопировать config.yaml если отсутствует"
	@echo "  make run                - запустить экспорт каналов"
	@echo "  make clean              - удалить артефакты (кэш .pyc, __pycache__)"
	@echo "  make purge              - полная очистка: clean + удаление .venv"
	@echo "  make config             - создать config.yaml из примера, если его нет"
	@echo "  make install-systemd    - установить systemd юниты и запустить таймер (SCOPE=user|system, TIMER_CALENDAR='daily' или '*-*-* 03:00')"
	@echo "  make uninstall-systemd  - остановить и удалить systemd юниты"
	@echo "  make systemd-status     - показать статус таймера и сервиса"
	@echo "  make systemd-run-once   - однократно запустить сервис вручную"
	@echo "  make systemd-reinstall  - перегенерировать юниты и перезапустить таймер"
	@echo "  make systemd-reload     - выполнить systemctl daemon-reload"
	@echo "  make systemd-restart    - перезапустить сервис вручную"
	@echo "  make systemd-env        - создать env-файл из примера (systemd/telegram-channels-to-md.env)"
	@echo "  make install-systemd    - установить systemd юниты и запустить таймер (SCOPE=user|system, TIMER_CALENDAR='daily' или '*-*-* 03:00')"
	@echo "  make uninstall-systemd  - остановить и удалить systemd юниты"
	@echo "  make systemd-status     - показать статус таймера и сервиса"
	@echo "  make systemd-run-once   - однократно запустить сервис вручную"

venv:
	@if [ ! -d "$(VENV_DIR)" ]; then python3 -m venv "$(VENV_DIR)"; fi

install: venv
	@$(PIP) install --upgrade pip setuptools wheel
	@$(PIP) install telethon pyyaml

config:
	@if [ ! -f "config.yaml" ]; then \
		cp "config.example.yaml" "config.yaml"; \
		echo "Скопирован config.yaml. Укажите свои telegram.api_id и telegram.api_hash."; \
	else \
		echo "config.yaml уже существует"; \
	fi

init: install config
	@echo "Инициализация завершена."

run: venv
	@$(PY) download_channels.py

clean:
	@find . -type d -name "__pycache__" -prune -exec rm -rf {} + || true
	@find . -type f -name "*.pyc" -delete || true
	@find . -type f -name "*.pyo" -delete || true

purge: clean
	@rm -rf "$(VENV_DIR)"

install-systemd:
	@echo "Установка systemd юнитов в $(SCOPE) scope; UNIT_DIR=$(UNIT_DIR)"
	@mkdir -p "$(UNIT_DIR)"
	@chmod +x "scripts/export_and_push.sh"
	@if [ "$(SCOPE)" = "user" ]; then \
		sed -e 's|@REPO_DIR@|$(REPO_DIR)|g' \
		    -e '/@RUN_AS_USER@/d' \
		    -e '/@RUN_AS_HOME@/d' \
		    "$(SERVICE_SRC)" > "$(UNIT_DIR)/$(UNIT_NAME).service"; \
	else \
		sed -e 's|@REPO_DIR@|$(REPO_DIR)|g' \
		    -e 's|@RUN_AS_USER@|$(RUN_AS_USER)|g' \
		    -e 's|@RUN_AS_HOME@|$(RUN_AS_HOME)|g' \
		    "$(SERVICE_SRC)" > "$(UNIT_DIR)/$(UNIT_NAME).service"; \
	fi
	@sed -e 's|@TIMER_CALENDAR@|$(TIMER_CALENDAR)|g' "$(TIMER_SRC)" > "$(UNIT_DIR)/$(UNIT_NAME).timer"
	@$(SYSTEMCTL) daemon-reload
	@$(SYSTEMCTL) enable --now "$(UNIT_NAME).timer"
	@echo "Готово: таймер запущен. Календарь: $(TIMER_CALENDAR)"

uninstall-systemd:
	@echo "Отключение и удаление systemd юнитов из $(UNIT_DIR)"
	-@$(SYSTEMCTL) disable --now "$(UNIT_NAME).timer"
	-@$(SYSTEMCTL) stop "$(UNIT_NAME).service"
	@rm -f "$(UNIT_DIR)/$(UNIT_NAME).timer" "$(UNIT_DIR)/$(UNIT_NAME).service"
	@$(SYSTEMCTL) daemon-reload
	@echo "Готово: юниты удалены."

systemd-status:
	-@$(SYSTEMCTL) status "$(UNIT_NAME).timer"
	-@$(SYSTEMCTL) status "$(UNIT_NAME).service"
	-@$(SYSTEMCTL) list-timers --all | grep -E '(^| )$(UNIT_NAME)\.timer' || true

systemd-run-once:
	@$(SYSTEMCTL) start "$(UNIT_NAME).service"

systemd-reinstall:
	@echo "Переустановка systemd юнитов в $(SCOPE) scope; UNIT_DIR=$(UNIT_DIR)"
	@mkdir -p "$(UNIT_DIR)"
	@chmod +x "scripts/export_and_push.sh"
	@if [ "$(SCOPE)" = "user" ]; then \
		sed -e 's|@REPO_DIR@|$(REPO_DIR)|g' \
		    -e '/@RUN_AS_USER@/d' \
		    -e '/@RUN_AS_HOME@/d' \
		    "$(SERVICE_SRC)" > "$(UNIT_DIR)/$(UNIT_NAME).service"; \
	else \
		sed -e 's|@REPO_DIR@|$(REPO_DIR)|g' \
		    -e 's|@RUN_AS_USER@|$(RUN_AS_USER)|g' \
		    -e 's|@RUN_AS_HOME@|$(RUN_AS_HOME)|g' \
		    "$(SERVICE_SRC)" > "$(UNIT_DIR)/$(UNIT_NAME).service"; \
	fi
	@sed -e 's|@TIMER_CALENDAR@|$(TIMER_CALENDAR)|g' "$(TIMER_SRC)" > "$(UNIT_DIR)/$(UNIT_NAME).timer"
	@$(SYSTEMCTL) daemon-reload
	@$(SYSTEMCTL) reenable "$(UNIT_NAME).timer" || true
	@$(SYSTEMCTL) restart "$(UNIT_NAME).timer"
	@echo "Готово: таймер перезапущен. Календарь: $(TIMER_CALENDAR)"

systemd-reload:
	@$(SYSTEMCTL) daemon-reload

systemd-restart:
	@$(SYSTEMCTL) restart "$(UNIT_NAME).service"

systemd-env:
	@if [ -f "systemd/telegram-channels-to-md.env.example" ] && [ ! -f "systemd/telegram-channels-to-md.env" ]; then \
		cp "systemd/telegram-channels-to-md.env.example" "systemd/telegram-channels-to-md.env"; \
		echo "Создан systemd/telegram-channels-to-md.env из примера"; \
	else \
		echo "Env файл уже существует или нет примера"; \
	fi