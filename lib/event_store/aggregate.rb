module EventStore
  class Aggregate

    def initialize id, type
      @id = id.to_s
      @type = type
    end

    def events
      @events ||= EventStore.db.from("#{@type}_events").where(:aggregate_id => @id.to_s).order(:version)
    end

    def last_event_of_each_type
      recent_event_versions = events.order(nil).group(:fully_qualified_name).select{ max(:version) }
      events.where(:version => recent_event_versions)
    end

  end
end