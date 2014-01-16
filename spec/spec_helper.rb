require 'simplecov'
require 'simplecov-rcov'

class SimpleCov::Formatter::MergedFormatter
  def format(result)
     SimpleCov::Formatter::HTMLFormatter.new.format(result)
     SimpleCov::Formatter::RcovFormatter.new.format(result)
  end
end
SimpleCov.formatter = SimpleCov::Formatter::MergedFormatter

SimpleCov.start do
  add_filter "/spec/"
  SimpleCov.minimum_coverage 95
end

require 'rspec'
require 'sequel'
require 'sequel/extensions/migration'
require 'event_store'

def test_db
  Sequel.connect('sqlite://db/event_store_test.db')
  # Sequel.connect('postgres://localhost:5432/nexia_event_store_development')
end
Sequel::Migrator.apply(test_db, File.expand_path('db/migrations'))

EventStore.connect :adapter => :sqlite, :database => 'db/event_store_test.db'

RSpec.configure do |config|
  config.after(:each) do
    EventStore::Snapshot.delete
    EventStore.db.from(:device_events).delete
  end
end