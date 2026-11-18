# syntax=docker/dockerfile:1
# Microservicio registro del Ejecutivo. Contexto de construcción: backend/
#   docker build -f services/registro/Dockerfile --target runtime -t sgsc-registro .
#   docker build -f services/registro/Dockerfile --target test .   (ejecuta sus pruebas)
# La imagen solo contiene sgsc_common y este servicio: nunca .env, ca.pem ni otros servicios.
ARG PYTHON_IMAGE=python:3.12-slim

FROM ${PYTHON_IMAGE} AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1 \
    FORWARDED_ALLOW_IPS=127.0.0.1
RUN useradd --create-home --uid 10001 sgsc
WORKDIR /app
COPY services/registro/requirements.txt /tmp/requirements.txt
COPY libs/sgsc_common /tmp/sgsc_common
RUN pip install -r /tmp/requirements.txt /tmp/sgsc_common && rm -rf /tmp/requirements.txt /tmp/sgsc_common
COPY services/registro/sgsc_registro ./sgsc_registro
USER sgsc
EXPOSE 8000
# --proxy-headers solo confía en la IP del gateway (FORWARDED_ALLOW_IPS, definida en docker-compose.yml).
CMD ["sh", "-c", "exec uvicorn sgsc_registro.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips=\"$FORWARDED_ALLOW_IPS\""]

FROM runtime AS test
USER root
COPY services/registro/requirements-test.txt /tmp/requirements-test.txt
RUN pip install -r /tmp/requirements-test.txt && rm /tmp/requirements-test.txt
COPY services/registro/pytest.ini ./pytest.ini
COPY services/registro/tests ./tests
USER sgsc
RUN python -m pytest -q
