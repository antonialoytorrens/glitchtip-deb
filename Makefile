#!/usr/bin/make -f

PYTHON ?= python3.13
PYPROJECT := packages/glitchtip/pyproject.toml
REQUIREMENTS := packages/glitchtip/requirements.txt

.PHONY: all requirements

all:
	docker build --target artifact --output . .

requirements:
	$(PYTHON) -m venv .venv-requirements
	.venv-requirements/bin/pip install --no-cache-dir --upgrade pip pip-tools
	.venv-requirements/bin/pip-compile \
	  --generate-hashes \
	  --resolver=backtracking \
	  --output-file=$(REQUIREMENTS) \
	  $(PYPROJECT)
	@echo ">>> $(REQUIREMENTS) updated (runtime deps only, no dev groups)"
