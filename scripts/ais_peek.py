import asyncio
import json
import os

import websockets

API_KEY = os.environ["AISSTREAM_API_KEY"]
URL = "wss://stream.aisstream.io/v0/stream"


async def main():
    async with websockets.connect(URL) as ws:
        subscription = {
            "APIKey": API_KEY,
            "BoundingBoxes": [[[40.0, 26.0], [41.5, 30.0]]],
        }
        await ws.send(json.dumps(subscription))

        for i in range(5):
            message = await ws.recv()
            data = json.loads(message)
            print(json.dumps(data, indent=2))


asyncio.run(main())