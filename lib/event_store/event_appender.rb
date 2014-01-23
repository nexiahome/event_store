module EventStore
  class EventAppender

    def initialize aggregate
      @aggregate = aggregate
    end

    def append raw_events
      EventStore.db.transaction do
        prepared_events = raw_events.map do |raw_event|
          event = prepare_event(raw_event)
          validate! event
          raise concurrency_error if has_concurrency_issue?(event)
          event
        end

        # All concurrency issues need to be checked before persisting any of the events
        # Otherwise, the newly appended events may raise erroneous concurrency errors
        @aggregate.events.multi_insert(prepared_events)
      end
    end

    private

    def concurrency_issue_possible?
      @potential_concurrency_issue ||= begin
        last_event = @aggregate.last_event
        last_event && expected_version < last_event[:version]
      end
    end

    def has_concurrency_issue? event
      if concurrency_issue_possible?
        last_event_of_type = @aggregate.last_event_of_type(event[:fully_qualified_name])
        last_event_of_type && expected_version < last_event_of_type[:version]
      else
        false
      end
    end

    def prepare_event raw_event
      { :aggregate_id         => raw_event.aggregate_id,
        :occurred_at          => raw_event.occurred_at,
        :serialized_event     => raw_event.serialized_event,
        :fully_qualified_name => raw_event.fully_qualified_name }
    end

    def concurrency_error
      ConcurrencyError.new("Expected version #{@expected_version} does not occur after last version")
    end

    private

    def expected_version
      @expected_version ||= begin
        last_event = @aggregate.last_event
        last_event ? last_event[:version] + 1 : Float::INFINITY
      end
    end

    def validate! event_hash
      [:aggregate_id, :fully_qualified_name, :occurred_at, :serialized_event].each do |attribute_name|
        if event_hash[attribute_name].to_s.strip.empty?
          raise AttributeMissingError, "value required for #{attribute_name}"
        end
      end
    end

  end
end