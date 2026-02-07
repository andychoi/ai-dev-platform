FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8100

HEALTHCHECK --interval=5s --timeout=3s --start-period=3s --retries=2 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8100/health')"

CMD ["gunicorn", "--bind", "0.0.0.0:8100", "--workers", "1", "--timeout", "30", "app:app"]
