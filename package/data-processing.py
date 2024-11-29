# Understanding of the problem section

# 2b (i)
# Correlate the bus location and weather data => I have combined them on location and sort by timestamps
# Identify delays caused by adverse weather => I have defined adverse weather as snow or rain with temperature < 0


# 2b (ii)
# Correlate van service with bus location and number of waiting passenger
# Used random to generate both average passenger count from history and waiting passenger
# Check weather conditions are met if van is required or not

# Load and parse json data for bus and van location and weather --Done
# Correlate bus locations with weather data --Done
# Identify conditions like "snow" or "rain" combined with freezing temperatures to flag delays. --Done
# Correlate van services with bus locations and the number of waiting passengers. --Done

# Import necessary libraries
import boto3 # type: ignore # # Import Boto3 to interact with AWS services
import pandas as pd # type: ignore
import json # type: ignore
import base64 # type: ignore
import numpy as np # type: ignore
from tabulate import tabulate # type: ignore


# Initialize DynamoDB resource and Kinesis client
dynamodb = boto3.resource('dynamodb')

# Reference the DynamoDB table that stores processed data
insights_table = dynamodb.Table('insights_table')


# Define the lambda handler function
def lambda_handler(event, context):

    bus_location_data = []
    van_location_data = []
    weather_data = []

    for record in event["Records"]:
        # Decode the Kinesis data from base64 and load it as JSON
        pk = record["kinesis"]["partitionKey"]
        msg = base64.b64decode(record["kinesis"]["data"]).decode("utf-8")
        data = json.loads(msg)

        for item in data:
            # Validate the data, Ensuring data quality by filtering out incomplete or malformed data.
            if 'bus_id' in item and 'lat' in item and 'lon' in item and 'timestamp' in item:
                bus_location_data.append(item)
            
            if 'van_id' in item and 'lat' in item and 'lon' in item and 'timestamp' in item:
                van_location_data.append(item)
            
            if 'lat' in item and 'lon' in item and 'temp' in item and 'precipitation' in item and 'timestamp' in item:
                weather_data.append(item)

    # Convert lists to DataFrames
    bus_location_data = pd.DataFrame(bus_location_data)
    van_location_data = pd.DataFrame(van_location_data)
    weather_data = pd.DataFrame(weather_data)

    # Convert timestamp to datetime
    bus_location_data['timestamp'] = pd.to_datetime(bus_location_data['timestamp'])
    weather_data['timestamp'] = pd.to_datetime(weather_data['timestamp'], errors='coerce')

    # Randomly generate average passengers for each stop
    bus_location_data["average_passenger_count"] = np.random.randint(10, 50, size=len(bus_location_data))
    # Randomly generate current passengers for each stop
    bus_location_data["passengers_waiting"] = np.random.randint(10, 100, size=len(bus_location_data))


    # Correlate bus locations with weather data
    bus_weather_correlated_data = pd.merge_asof(bus_location_data.sort_values("timestamp"), weather_data.sort_values("timestamp"), on="timestamp", by=["lat", "lon"])
    #print(bus_weather_correlated_data)


    # Next we need to identify delays caused by adverse weather
    # We  an use lamba and define adverse weather as snow and rain in precipitation column AND temp < 0 in temp column
    # For example, we can filter for snow or rain and freezing temperatures
    bus_weather_correlated_data['delay_reason'] = bus_weather_correlated_data.apply(
        lambda row: 'adverse weather' if row['precipitation'] in ['snow', 'rain'] and row['temp'] < 0 else 'normal weather',
        axis=1
    )

    # Randomly generate delay times (in minutes)
    # using seed ensure we get same random number everytime we ran the code
    np.random.seed(42)

    bus_weather_correlated_data['delay_time'] = np.random.randint(0, 10, len(bus_weather_correlated_data))

    #print(bus_weather_correlated_data)

    # insert bus_weather_correlated_data in a DynamoDB table (INSIGHTS TABLE)
    insights_table.put_item(bus_weather_correlated_data)


    # Next we need to correlate van services with bus locations and the number of waiting passengers.
    # Check whether a van is needed depending on the condition

    def calculate_van_needed(row):
        condition1 = row["delay_time"] > 5  # Delay time > 5 minutes
        condition2 = row["passengers_waiting"] > 0.5 * row["average_passenger_count"]  # Passengers > 50% of average
        return condition1 and condition2


    bus_weather_correlated_data["van_required"] = bus_weather_correlated_data.apply(calculate_van_needed, axis=1)


    #print("\n=== Full Data with Van Requirements ===")
    #print(tabulate(bus_weather_correlated_data, headers="keys", tablefmt="pretty"))
    return {
        'statusCode': 200,
    }
