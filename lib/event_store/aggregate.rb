module EventStore
  class Aggregate

    def initialize id, type
      @id = id
      @type = type
      @event_table = "#{@type}_events"
      @snapshot_table = "#{@type}_snapshots"
    end

    def events
      @aggregate_events_query ||= EventStore.db.from(@event_table).where(:aggregate_id => @id.to_s).order(:version)
    end

    def events_from(version_number, max = nil)
      events.limit(max).where{ version >= version_number.to_i }
    end

    def last_event
      events.limit(1).last
    end

    def last_event_of_type(fully_qualified_name)
      events.where(fully_qualified_name: fully_qualified_name).order(:version).limit(1).last
    end

    def last_event_of_each_type
      #Order of magnitude faster than a group by query
      @last_event_of_type_query ||= EventStore.db.fetch(
      "SELECT event_1.*
        FROM #{@event_table} event_1 LEFT JOIN #{@event_table} event_2
        ON (event_1.fully_qualified_name = event_2.fully_qualified_name AND event_1.version < event_2.version)
        WHERE  event_1.aggregate_id = '#{@id}' AND event_2.version IS NULL;"
      )
      @last_event_of_type_query
    end

    def snapshot_query
      @snapshot_query ||=  EventStore.db.from(@snapshot_table).where(:aggregate_id => @id.to_s).limit(1)
    end

    def snapshot
      @snapshot = snapshot_query.first
      return [] unless @snapshot
      snapshot = @snapshot[:snapshot]
      cached_events = []
      snapshot.each_pair do |event_name, serialized_event|
        cached_events << EventStore::SerializedEvent.new(event_name, serialized_event)
      end
      cached_events
    end
  end
end