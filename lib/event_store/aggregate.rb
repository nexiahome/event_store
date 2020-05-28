require 'forwardable'

module EventStore
  class Aggregate
    extend Forwardable

    attr_reader :id, :type, :event_table, :snapshot, :event_stream, :checkpoint_events

    def_delegators :snapshot,
      :last_event,
      :rebuild_snapshot!,
      :delete_snapshot!,
      :event_id,
      :event_id_for,
      :snapshot_event_id_table

    def_delegators :event_stream,
      :events,
      :snapshot_events,
      :events_from,
      :event_stream_between,
      :event_table,
      :last_event_before,
      :delete_events!

    def snapshot_exists?
      @snapshot.exists?
    end

    def self.count
      EventStore.db.from(EventStore.fully_qualified_table).select(:aggregate_id).distinct.count
    end

    def self.ids(offset, limit)
      EventStore.db.from(EventStore.fully_qualified_table).select(:aggregate_id).distinct.order(:aggregate_id).limit(limit, offset).all.map{|item| item[:aggregate_id]}
    end

    def initialize(id, type = EventStore.table_name, checkpoint_events = [])
      @id = id
      @type = type

      @checkpoint_events = checkpoint_events
      @snapshot          = Snapshot.new(self)
      @event_stream      = EventStream.new(self)
    end

    def append(events, logger)
      if EventStore.save_event_history?
        logger.debug("EventStore#append, appending to event stream")
        event_stream.append(events, logger) do |prepared_events|
          logger.debug("EventStore#append, storing snapshot")
          snapshot.store_snapshot(prepared_events, logger)
        end
      end
    end

  end
end
