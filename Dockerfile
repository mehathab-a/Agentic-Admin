FROM python:3.11-slim AS builder
RUN pip install --no-cache-dir uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv export --no-dev --no-emit-project --no-hashes --format requirements.txt > requirements.txt \
 && pip install --no-cache-dir --timeout 120 --retries 10 --prefix=/install -r requirements.txt

FROM python:3.11-slim
RUN useradd -m -u 1000 app
COPY --from=builder /install /usr/local
WORKDIR /app
COPY app/ ./app/
USER app
EXPOSE 8000
CMD ["uvicorn", "app.api:app", "--host", "0.0.0.0", "--port", "8000"]