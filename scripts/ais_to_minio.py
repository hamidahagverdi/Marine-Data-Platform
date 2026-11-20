import asyncio
import json
import os
from datetime import datetime, timezone

import boto3
import websockets
from botocore.config import Config

AIS_URL = "wss://stream.aisstream.io/v0/stream"
API_KEY = os.environ["AISSTREAM_API_KEY"]
BOUNDING_BOX = [[40.0, 26.0], [41.5, 30.0]]
MESSAGE_COUNT = 50

s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["MINIO_ENDPOINT"],
    aws_access_key_id=os.environ["MINIO_USER"],
    aws_secret_access_key=os.environ["MINIO_PASSWORD"],
    config=Config(s3={"addressing_style": "path"}),
)


async def collect_messages():
    messages = []
    async with websockets.connect(AIS_URL, open_timeout=30) as ws: 
        subscription = {"APIKey": API_KEY, "BoundingBoxes": [BOUNDING_BOX]}
        await ws.send(json.dumps(subscription))

        while len(messages) < MESSAGE_COUNT:
            data = json.loads(await ws.recv())
            if data.get("MessageType") == "SubscriptionConfirmation":
                continue
            messages.append(data)
            print(f"{len(messages)}/{MESSAGE_COUNT} mesaj alındı")
    return messages


def upload(messages):
    now = datetime.now(timezone.utc)
    key = f"ais/raw/date={now:%Y-%m-%d}/{now:%H%M%S}.jsonl"
    body = "\n".join(json.dumps(m) for m in messages)
    s3.put_object(Bucket="bronze", Key=key, Body=body.encode("utf-8"))
    print(f"Yazıldı: s3://bronze/{key}")


messages = asyncio.run(collect_messages())
upload(messages)