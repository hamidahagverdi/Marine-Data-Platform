FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --default-timeout=120 --retries 10 -r requirements.txt

COPY ais_ingestor.py .

USER 1000

CMD ["python", "ais_ingestor.py"]