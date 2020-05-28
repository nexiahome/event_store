module EventStore
  class EventStream
    include Enumerable

    attr_reader :event_table, :checkpoint_events

    def initialize aggregate
      @aggregate = aggregate
      @id = @aggregate.id
      @checkpoint_events = aggregate.checkpoint_events
      @event_table_alias = "events"
      @event_table = Sequel.qualify(EventStore.schema, EventStore.table_name)
      @aliased_event_table = event_table.as(@event_table_alias)
      @names_table = EventStore.fully_qualified_names_table
    end

    def append(raw_events, logger)
      if EventStore.save_event_history?
        prepared_events = raw_events.map do |raw_event|
          event = prepare_event(raw_event)
          ensure_all_attributes_have_values!(event)
          event
        end

        prepared_events.each do |event|
          event_hash = event.dup.reject! { |k,v| k == :fully_qualified_name }
          event_table = insert_table(Time.now)

          begin
            id = event_table.insert(event_hash)
          rescue Sequel::NotNullConstraintViolation
            fully_qualified_names.insert(fully_qualified_name: event[:fully_qualified_name])
            id = event_table.insert(event_hash)
          end

          logger.debug("EventStream#append, setting id #{id} for #{event_hash.inspect}")

          event[:id] = id
        end

        yield(prepared_events) if block_given?
      end
    end

    def insert_table(occurred_at)
      EventStore.db.from(insert_table_name(occurred_at))
    end

    def insert_table_name(date)
      EventStore.insert_table_name(date)
    end

    def fully_qualified_names
      @fully_qualified_name_query ||= EventStore.db.from(@names_table)
    end

    def events
      @events_query ||=
        begin
          query = EventStore.db.from(@aliased_event_table).where(:aggregate_id => @id.to_s)
          query = query.join(@names_table, id: :fully_qualified_name_id) if EventStore.use_names_table?
          query = query.order { events[:id] }.select_all(:events)
          query = query.select_append(:fully_qualified_name) if EventStore.use_names_table?
          query
        end
    end

    def snapshot_events
      last_checkpoint = nil

      if checkpoint_events
        checkpoints = last_event_before(Time.now.utc, checkpoint_events)

        last_checkpoint = checkpoints.first # start at the earliest possible place
      end

      if last_checkpoint
        events.where{ events[:id] >= last_checkpoint[:id].to_i }
      else
        events
      end
    end

    def events_from(event_id, max = nil)
      # note: this depends on the events table being aliased to "events" above.
      events.limit(max).where{events[:id] >= event_id.to_i }.all.map do |event|
        event[:serialized_event] = EventStore.unescape_bytea(event[:serialized_event])
        event
      end
    end

    # Private: returns the last event before start_time for each of the events named
    #         by fully_qualified_names.
    #
    # Generates queries that look like this:
    #
    #     SELECT events.*, fully_qualified_name
    #       FROM event_store.thermostat_events "events"
    # INNER JOIN event_store.fully_qualified_names fqn ON fqn.id = fully_qualified_name_id
    #      WHERE events.id IN (SELECT max(events.id) from event_store.thermostat_events "events"
    #                      INNER JOIN event_store.fully_qualified_names fqn ON fqn.id = fully_qualified_name_id
    #                           WHERE occurred_at < '2016-08-08 06:00:00'
    #                             AND fully_qualified_name = 'faceplate_api.system.core.events.HeatingStageStarted'
    #                        GROUP BY sub_key);
    #
    def last_event_before(start_time, fully_qualified_names = [])
      timestampz = start_time.strftime("%Y-%m-%d %H:%M:%S%z")

      rows = fully_qualified_names.inject([]) { |memo, name|
        memo + events.where(Sequel.qualify("events", "id") => events.where(fully_qualified_name: name).where { occurred_at < timestampz }
                 .select { max(events[:id]) }.unordered.group(:sub_key)).all
      }.sort_by { |r| r[:occurred_at] }

      rows.map {|r| r[:serialized_event] = EventStore.unescape_bytea(r[:serialized_event]); r}
    end

    # Private: returns the last event before start_time for each of the events named
    #          by fully_qualified_names. Doesn't work when events have multiple valid
    #          sub_keys, but is fast when they don't.
    #
    # Generates queries that look like this:
    #
    #     SELECT events.*, fully_qualified_name
    #       FROM event_store.thermostat_events "events"
    # INNER JOIN event_store.fully_qualified_names fqn ON fqn.id = fully_qualified_name_id
    #      WHERE occurred_at < '2016-08-08 06:00:00'
    #        AND fully_qualified_name = 'faceplate_api.system.core.events.HeatingStageStarted'
    #   ORDER BY occurred_at DESC LIMIT 1;
    #
    def simple_last_event_before(start_time, fully_qualified_names = [])
      timestampz = start_time.strftime("%Y-%m-%d %H:%M:%S%z")

      rows = fully_qualified_names.inject([]) { |memo, name|
        memo + events.where(fully_qualified_name: name).where{ occurred_at < timestampz }
                 .reverse_order(:occurred_at, :id).limit(1).all
      }.sort_by { |r| r[:occurred_at] }

      rows.map {|r| r[:serialized_event] = EventStore.unescape_bytea(r[:serialized_event]); r}
    end

    def event_stream_between(start_time, end_time, fully_qualified_names = [])
      query = events.where(occurred_at: start_time..end_time)
      query = query.where(fully_qualified_name: fully_qualified_names) if fully_qualified_names && fully_qualified_names.any?
      query.all.map {|e| e[:serialized_event] = EventStore.unescape_bytea(e[:serialized_event]); e}
    end

    def last
      to_a.last
    end

    def empty?
      events.empty?
    end

    def each
      events.all.each do |e|
        e[:serialized_event] = EventStore.unescape_bytea(e[:serialized_event])
        yield e
      end
    end

    def delete_events!
      EventStore.db.from(@event_table).where(:aggregate_id => @id.to_s).delete
    end

  private

    def prepare_event(raw_event)
      raise ArgumentError.new("Cannot Append a Nil Event") unless raw_event
      { :aggregate_id            => raw_event.aggregate_id,
        :occurred_at             => Time.parse(raw_event.occurred_at.to_s).utc, #to_s truncates microseconds, which breaks Time equality
        :serialized_event        => EventStore.escape_bytea(raw_event.serialized_event),
        :fully_qualified_name    => raw_event.fully_qualified_name,
        :sub_key                 => raw_event.sub_key
      }.tap { |event_info|
        if EventStore.use_names_table?
          name_subquery = EventStore.db.from(@names_table).where(fully_qualified_name: raw_event.fully_qualified_name).select(:id)
          event_info[:fully_qualified_name_id] = name_subquery
        end
      }
    end

    def ensure_all_attributes_have_values!(event_hash)
      [:aggregate_id, :fully_qualified_name, :occurred_at, :serialized_event].each do |attribute_name|
        if event_hash[attribute_name].to_s.strip.empty?
          raise AttributeMissingError, "value required for #{attribute_name}"
        end
      end
    end
  end
end
