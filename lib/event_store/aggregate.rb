module EventStore
  class Aggregate

    attr_reader :id, :type

    def initialize id, type
      @id = id.to_s
      @type = type
    end

    def events
      @events ||= EventStore.db.from("#{@type}_events").where(:aggregate_id => @id.to_s).order(:version)
    end

    def last_event_of_each_type
      snapshot = Snapshot.latest_for_aggregate(self)
      if snapshot
        recent_events = most_recent_events_per_type_since(snapshot.event_ids.max)
        missing_event_types = snapshot.event_types - recent_events.map{ |e| e[:fully_qualified_name] }
        [recent_events, snapshot.events.where(:fully_qualified_name => missing_event_types)].map(&:to_a).inject(&:+)
      else
        most_recent_events_per_type_since(0).to_a
      end
    end

    private

    def most_recent_events_per_type_since(event_version)
      recent_event_versions = events.order(nil).group(:fully_qualified_name).select{ max(:version) }
      events.where(:version => recent_event_versions)
    end

  end
end