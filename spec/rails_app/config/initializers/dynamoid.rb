# frozen_string_literal: true

require 'dynamoid'

Dynamoid.configure do |config|
  # Testing with [DynamoDB Local] (http://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Tools.DynamoDBLocal.html).
  config.access_key = 'dummy'
  config.secret_key = 'dummy'
  config.endpoint = 'http://localhost:8000'
  config.region = 'us-west-2'

  config.http_open_timeout = 2
  config.http_read_timeout = 5
end
