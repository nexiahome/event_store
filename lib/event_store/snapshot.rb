module EventStore
  class Snapshot < Sequel::Model(:event_store_snapshots)

    PACKING_FORMAT = 'U'

    def self.latest_for_aggregate(aggregate)
      where(:aggregate_id => aggregate.id.to_s, :aggregate_type => aggregate.type.to_s).order(Sequel.desc(:id)).limit(1).first
    end

    def event_ids
      self[:event_ids].unpack(PACKING_FORMAT * self[:event_ids].length)
    end

    def event_ids=(ids)
      self[:event_ids] = ids.pack(PACKING_FORMAT * ids.length)
    end

    def events
      @events ||= aggregate.events.where(:version => event_ids)
    end

    def event_types
      events.map{ |e| e[:fully_qualified_name] }
    end

    private

    def aggregate
      @aggregate ||= Aggregate.new(aggregate_id, aggregate_type)
    end

  end
end