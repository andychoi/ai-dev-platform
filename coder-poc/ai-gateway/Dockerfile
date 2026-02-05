# AI Gateway for Coder WebIDE PoC
# Multi-provider AI API proxy with rate limiting and audit logging

FROM python:3.11-slim

LABEL maintainer="Platform Team"
LABEL description="Multi-provider AI API Gateway"
LABEL version="1.0.0"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash gateway

# Set working directory
WORKDIR /app

# Copy requirements first for caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create log directory
RUN mkdir -p /var/log/ai-gateway && chown gateway:gateway /var/log/ai-gateway

# Switch to non-root user
USER gateway

# Expose port
EXPOSE 8090

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8090/health || exit 1

# Run the gateway
CMD ["python", "gateway.py"]
