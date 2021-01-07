require "ostruct"
require "rspec"

require "event_store"
require "ruby2_keywords"
require "mock_redis"

# connect to the test db for the gem, create to ensure exists, delete and re-create
EventStore.postgres("test", "test_events", "event_store_gem_test")
EventStore.create_db
EventStore.clear!
EventStore.create_db

RSpec.configure do |config|
  config.after(:each) do
    EventStore.clear!
  end
end
