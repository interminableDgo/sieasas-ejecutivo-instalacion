# syntax=docker/dockerfile:1
# Microservicio indicadores del Ejecutivo. Contexto de construcción: backend/
#   docker build -f services/indicadores/Dockerfile --target runtime -t sgsc-indicadores .
#   docker build -f services/indicadores/Dockerfile --target test .   (ejecuta sus pruebas)
# La imagen solo contiene sgsc_common y este servicio: nunca .env, ca.pem ni otros servicios.
ARG PYTHON_IMAGE=python:3.12-slim

FROM ${PYTHON_IMAGE} AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1 \
    FORWARDED_ALLOW_IPS=127.0.0.1 PYTHONPATH=/app
RUN useradd --create-home --uid 10001 sgsc
WORKDIR /app
# Dependencias fijadas con hashes (requirements.docker.lock) y solo paquetes precompilados:
# pip no ejecuta scripts de instalación. sgsc_common se copia como código (PYTHONPATH=/app).
COPY services/indicadores/requirements.docker.lock /tmp/requirements.lock
RUN pip install --only-binary :all: --require-hashes --no-deps -r /tmp/requirements.lock && rm /tmp/requirements.lock
COPY libs/sgsc_common/sgsc_common ./sgsc_common
COPY services/indicadores/sgsc_indicadores ./sgsc_indicadores
USER sgsc
EXPOSE 8000
# --proxy-headers solo confía en la IP del gateway (FORWARDED_ALLOW_IPS, definida en docker-compose.yml).
CMD ["sh", "-c", "exec uvicorn sgsc_indicadores.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips=\"$FORWARDED_ALLOW_IPS\""]

FROM runtime AS test
USER root
COPY services/indicadores/requirements-test.docker.lock /tmp/requirements-test.lock
RUN pip install --only-binary :all: --require-hashes --no-deps -r /tmp/requirements-test.lock && rm /tmp/requirements-test.lock
COPY services/indicadores/pytest.ini ./pytest.ini
COPY services/indicadores/tests ./tests
USER sgsc
RUN python -m pytest -q
