"""AIS ingestor: aisstream.io-dan gələn mesajları Kafka-ya yazır."""
import asyncio
import json
import os

import websockets
from confluent_kafka import Producer

AIS_URL = "wss://stream.aisstream.io/v0/stream"
API_KEY = os.environ["AISSTREAM_API_KEY"]
KAFKA_SERVERS = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "marine-kafka-kafka-bootstrap.kafka:9092")
TOPIC = os.environ.get("KAFKA_TOPIC", "ais.raw")
BOUNDING_BOX = json.loads(os.environ.get("BOUNDING_BOX", "[[40.0, 26.0], [41.5, 30.0]]"))

producer = Producer({"bootstrap.servers": KAFKA_SERVERS})


async def stream_once():
    async with websockets.connect(AIS_URL, open_timeout=30) as ws:
        subscription = {"APIKey": API_KEY, "BoundingBoxes": [BOUNDING_BOX]}
        await ws.send(json.dumps(subscription))
        print("aisstream.io-ya qoşuldu", flush=True)

        count = 0
        async for message in ws:
            data = json.loads(message)
            if data.get("MessageType") == "SubscriptionConfirmation":
                continue

            mmsi = data.get("MetaData", {}).get("MMSI")
            producer.produce(
                TOPIC,
                key=str(mmsi) if mmsi else None,
                value=json.dumps(data),
            )
            producer.poll(0)

            count += 1
            if count % 10 == 0:
                print(f"{count} mesaj Kafka-ya göndərildi", flush=True)


async def main():
    while True:
        try:
            await stream_once()
        except Exception as error:
            print(f"Əlaqə kəsildi: {error}. 10 saniyə sonra yenidən qoşulur...", flush=True)
            producer.flush()
            await asyncio.sleep(10)


asyncio.run(main())