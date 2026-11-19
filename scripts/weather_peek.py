import requests

URL = "https://marine-api.open-meteo.com/v1/marine"

params = {
    "latitude": 40.77,
    "longitude": 28.52,
    "hourly": "wave_height,wave_direction,wave_period",
    "forecast_days": 1,
    "timezone": "UTC",
}

response = requests.get(URL, params=params, timeout=30)
response.raise_for_status()
data = response.json()

print("Nöqtə:", data["latitude"], data["longitude"])
print("Vahidlər:", data["hourly_units"])
print()

hourly = data["hourly"]
for time, height, direction, period in zip(
    hourly["time"],
    hourly["wave_height"],
    hourly["wave_direction"],
    hourly["wave_period"],
):
    print(time, "| dalğa:", height, "m | istiqamət:", direction, "° | period:", period, "s")