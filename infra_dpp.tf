
# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Create the Kinesis Streams
resource "aws_kinesis_stream" "bus-location-stream" {
  name             = "bus-location-stream"
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

resource "aws_kinesis_stream" "van-location-stream" {
  name             = "van-location-stream"
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

resource "aws_kinesis_stream" "weather-stream" {
  name             = "weather-stream"
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}


# Create the DynamoDB Table for proceesed data
resource "aws_dynamodb_table" "insights_table" {
  name         = "insights_table"
  billing_mode = "PAY_PER_REQUEST"
  #read_capacity  = 20
  #write_capacity = 20
  hash_key = "timestamp"

  attribute {
    name = "timestamp"
    type = "S"
  }
}



# Create the IAM Role and Policy for the Lambda Functions
resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda_policy"
  role   = "${aws_iam_role.lambda_role.id}"
  policy = "${file("iam/lambda-policy.json")}"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"

  assume_role_policy = "${file("iam/lambda-assume-role.json")}"
}

# Archive a processing.py into a zip file
locals {
  lambda_processing_location = "outputs/processing.zip"
}

#data "archive_file" "processing" {
 # type        = "zip"
  #source_file = "${path.module}/Processing/processing.py"
  #output_path = local.lambda_processing_location
#}

# Create S3 bucket for Lambda code
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "mdpp-lambda-code-bucket"
}

# Enable versioning for the bucket
resource "aws_s3_bucket_versioning" "lambda_bucket_versioning" {
  bucket = aws_s3_bucket.lambda_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Upload Lambda zip to S3
resource "aws_s3_object" "lambda_processing" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "data-processing.zip"
  source = local.lambda_processing_location
  etag   = filemd5(local.lambda_processing_location)
}

# Create the Lambda Function for processing the data
resource "aws_lambda_function" "processing_lambda" {
  #filename      = local.lambda_processing_location
  function_name = "data-processing"
  role          = aws_iam_role.lambda_role.arn
  handler       = "data-processing.lambda_handler"

  s3_bucket         = aws_s3_bucket.lambda_bucket.id
  s3_key            = aws_s3_object.lambda_processing.key
  s3_object_version = aws_s3_object.lambda_processing.version_id

  source_code_hash = filebase64sha256(local.lambda_processing_location)

  runtime = "python3.11"

  environment {
    variables = {
      WEATHER_TABLE       = "weather_data"
      BUS_TABLE           = "bus_location_data"
      VAN_TABLE           = "van_location_data"
      PASSENGER_THRESHOLD = 50
      DELAY_THRESHOLD     = 300
      VAN_STREAM          = aws_kinesis_stream.van-location-stream.name
      BUS_STREAM          = aws_kinesis_stream.bus-location-stream.name
      WEATHER_STREAM      = aws_kinesis_stream.weather-stream.name
    }
  }

  depends_on = [aws_iam_role_policy.lambda_policy]

}

# Event source mapping for Lambda triggers
resource "aws_lambda_event_source_mapping" "van_location_trigger" {
  event_source_arn  = aws_kinesis_stream.van-location-stream.arn
  function_name     = aws_lambda_function.processing_lambda.arn
  starting_position = "LATEST"
}

resource "aws_lambda_event_source_mapping" "weather_trigger" {
  event_source_arn  = aws_kinesis_stream.weather-stream.arn
  function_name     = aws_lambda_function.processing_lambda.arn
  starting_position = "LATEST"
}

resource "aws_lambda_event_source_mapping" "bus_location_trigger" {
  event_source_arn  = aws_kinesis_stream.bus-location-stream.arn
  function_name     = aws_lambda_function.processing_lambda.arn
  starting_position = "LATEST"
}


# CloudWatch Metrics and Insights Dashboard
resource "aws_cloudwatch_dashboard" "insights_dashboard" {
  dashboard_name = "insights_dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric",
        x      = 0,
        y      = 0,
        width  = 12,
        height = 6,
        properties = {
          metrics = [
          ["AWS/DynamoDB", "SuccessfulRequestLatency", "TableName", "${aws_dynamodb_table.insights_table.name}"]
          ]
          title   = "Data Pipeline Insights",
          view    = "timeSeries",
          stacked = false,
          region = "us-east-1"
        }
      }
    ]
  })
}

