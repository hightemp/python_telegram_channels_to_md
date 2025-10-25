SHELL := /bin/bash

VENV_DIR := .venv
PY := $(VENV_DIR)/bin/python
PIP := $(VENV_DIR)/bin/pip

PROJECT := python_telegram_channels_to_md

.DEFAULT_GOAL := help

.PHONY: help init venv install run config clean purge

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