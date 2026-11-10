# Stage 1: Get official static Docker CLI
FROM docker:27-cli AS docker-cli

# Stage 2: Python runtime for FastAPI and Ansible
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    ANSIBLE_HOST_KEY_CHECKING=False

# Copy official static Docker CLI from Stage 1
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

WORKDIR /app

# Install Python requirements and community.docker collection
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && ansible-galaxy collection install community.docker:3.13.1

# Copy application source and Ansible assets
COPY app.py .
COPY ansible/ ./ansible/

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
