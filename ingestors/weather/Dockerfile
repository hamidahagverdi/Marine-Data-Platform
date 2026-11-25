FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
COPY wheels/ /wheels/
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt

COPY weather_ingestor.py .

USER 1000

CMD ["python", "weather_ingestor.py"]