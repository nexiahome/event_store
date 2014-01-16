require 'sequel'
require 'event_store/version'
require 'event_store/event_appender'
require 'event_store/aggregate'
require 'event_store/snapshot_creator'
require 'event_store/client'
require 'event_store/errors'

module EventStore

  Event = Struct.new(:aggregate_id, :occurred_at, :serialized_event, :fully_qualified_name)

  def self.db
    @db
  end

  def self.connect(*args)
    @db = Sequel.connect(*args)
    require 'event_store/snapshot'
    @db
  end
end
