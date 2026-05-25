FROM python:3.13-slim AS builder

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY Backend/requirements.txt ./requirements.txt
RUN pip install --prefix=/install --no-cache-dir -r requirements.txt

FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ENVIRONMENT=production

WORKDIR /app

RUN useradd --system --uid 10001 --create-home appuser

COPY --from=builder /install /usr/local
COPY Backend/app ./app
COPY Backend/alembic ./alembic
COPY Backend/alembic.ini ./alembic.ini
COPY Backend/main.py ./main.py
COPY Backend/infra/api-entrypoint.sh /usr/local/bin/life-organize-api-entrypoint

RUN chmod +x /usr/local/bin/life-organize-api-entrypoint \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

ENTRYPOINT ["life-organize-api-entrypoint"]
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "127.0.0.1"]
