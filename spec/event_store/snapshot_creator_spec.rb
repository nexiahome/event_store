require_relative '../spec_helper'

def create_events_for_aggregate aggregate, event_count
  event_ids = (1..event_count).map do |i|
    EventStore.db.from(:device_events).insert :aggregate_id => aggregate.id, :occurred_at => DateTime.now, :data => 234532.to_s(2), :fully_qualified_name => "e_#{i}"
  end
  EventStore.db.from(:device_events).where(:version => event_ids).to_a
end

describe EventStore::SnapshotCreator do
  before do
    @aggregate = EventStore::Aggregate.new(123, :device)
  end

  it "can find the latest snapshot" do
    snapshots = Array.new(2) { EventStore::Snapshot.create :aggregate_id => @aggregate.id, :aggregate_type => @aggregate.type, :event_ids => [1,2,3] }
    expect(EventStore::Snapshot.latest_for_aggregate(@aggregate)).to eq(snapshots.last)
  end

  context "#needs_new_snapshot?" do
    context "no pre-existing snapshot" do
      it "no snapshot needed" do
        expect(EventStore::SnapshotCreator.new(@aggregate).needs_new_snapshot?).to be_false
      end

      it "snapshot needed" do
        create_events_for_aggregate @aggregate, 101
        expect(EventStore::SnapshotCreator.new(@aggregate).needs_new_snapshot?).to be_true
      end
    end


    context "with a pre-existing snapshot" do
      it "no snapshot needed" do
        events = create_events_for_aggregate @aggregate, 10
        EventStore::Snapshot.create :aggregate_id => @aggregate.id, :aggregate_type => @aggregate.type, :event_ids => events.map{ |e| e[:version] }
        expect(EventStore::SnapshotCreator.new(@aggregate).needs_new_snapshot?).to be_false
      end

      it "snapshot needed" do
        events = create_events_for_aggregate @aggregate, 10
        EventStore::Snapshot.create :aggregate_id => @aggregate.id, :aggregate_type => @aggregate.type, :event_ids => events.map{ |e| e[:version] }
        create_events_for_aggregate @aggregate, 100
        expect(EventStore::SnapshotCreator.new(@aggregate).needs_new_snapshot?).to be_true
      end

    end
  end
end