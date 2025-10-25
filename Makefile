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

.DEFAULT_GOAL := help

.PHONY: help init venv install run config clean purge install-systemd uninstall-systemd systemd-status systemd-run-once

help:
	@echo "Доступные цели:"
	@echo "  make init     - создать venv, установить зависимости, скопировать config.yaml если отсутствует"
	@echo "  make run      - запустить экспорт каналов"
	@echo "  make clean    - удалить артефакты (кэш .pyc, __pycache__)"
	@echo "  make purge    - полная очистка: clean + удаление .venv"
	@echo "  make config   - создать config.yaml из примера, если его нет"

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
	@sed -e 's|@REPO_DIR@|$(REPO_DIR)|g' "$(SERVICE_SRC)" > "$(UNIT_DIR)/$(UNIT_NAME).service"
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