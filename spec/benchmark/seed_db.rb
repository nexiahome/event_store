require 'event_store'

EventStore.connect :adapter => :postgres, :database => 'event_store_performance', :host => 'localhost'

DEVICES = 30_000
EVENTS = 5_000_000
EVENT_TYPES = 100

event_types = Array.new(EVENT_TYPES) { |i| "event_type_#{i}" }

(1..DEVICES).each do |device_id|
  agg = EventStore::Aggregate.new(device_id, :device)
  (EVENTS/DEVICES).times do
    agg.event_class.create(aggregate_id: device_id, fully_qualified_name: event_types.sample, data: 9999999999999.to_s(2), occurred_at: DateTime.now)
  end
end