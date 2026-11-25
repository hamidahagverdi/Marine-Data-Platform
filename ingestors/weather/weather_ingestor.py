"""Hava ingestor: Open-Meteo-dan dəniz şəraitini oxuyub Kafka-ya yazır."""
import json
import os
from datetime import datetime, timezone

import requests
from confluent_kafka import Producer

API_URL = "https://marine-api.open-meteo.com/v1/marine"
KAFKA_SERVERS = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "marine-kafka-kafka-bootstrap.kafka:9092")
TOPIC = os.environ.get("KAFKA_TOPIC", "marine.weather")
POINTS = json.loads(os.environ.get("POINTS", "[[40.79, 28.54], [40.70, 28.00], [40.85, 29.05]]"))
VARIABLES = "wave_height,wave_direction,wave_period,wind_wave_height"

producer = Producer({"bootstrap.servers": KAFKA_SERVERS})
now = datetime.now(timezone.utc)
current_hour = now.strftime("%Y-%m-%dT%H:00")

sent = 0
for lat, lon in POINTS:
    params = {
        "latitude": lat,
        "longitude": lon,
        "hourly": VARIABLES,
        "forecast_days": 1,
        "timezone": "UTC",
    }
    response = requests.get(API_URL, params=params, timeout=30)
    response.raise_for_status()
    data = response.json()
    hourly = data["hourly"]

    if current_hour not in hourly["time"]:
        print(f"{lat},{lon}: {current_hour} üçün data yoxdur", flush=True)
        continue

    i = hourly["time"].index(current_hour)
    record = {
        "requested_lat": lat,
        "requested_lon": lon,
        "grid_lat": data["latitude"],
        "grid_lon": data["longitude"],
        "time_utc": current_hour,
        "fetched_at": now.isoformat(),
    }
    for name in VARIABLES.split(","):
        record[name] = hourly[name][i]

    key = f"{data['latitude']},{data['longitude']}"
    producer.produce(TOPIC, key=key, value=json.dumps(record))
    sent += 1
    print(f"{key}: dalğa {record['wave_height']} m", flush=True)

producer.flush()
print(f"Cəmi {sent} qeyd Kafka-ya göndərildi", flush=True)