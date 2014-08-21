require 'spec_helper'
require 'securerandom'
AGGREGATE_ID_ONE   = SecureRandom.uuid
AGGREGATE_ID_TWO   = SecureRandom.uuid
AGGREGATE_ID_THREE = SecureRandom.uuid

describe EventStore::Client do
  let(:es_client) { EventStore::Client }

  before do
    client_1 = es_client.new(AGGREGATE_ID_ONE, :device)
    client_2 = es_client.new(AGGREGATE_ID_TWO, :device)

    events_by_aggregate_id  = {AGGREGATE_ID_ONE => [], AGGREGATE_ID_TWO => []}
    @event_time = Time.parse("2001-01-01 00:00:00 UTC")
    ([AGGREGATE_ID_ONE]*10 + [AGGREGATE_ID_TWO]*10).shuffle.each_with_index do |aggregate_id, version|
      events_by_aggregate_id[aggregate_id.to_s] << EventStore::Event.new(aggregate_id.to_s, @event_time, 'event_name', serialized_binary_event_data, version)
    end
    client_1.append events_by_aggregate_id[AGGREGATE_ID_ONE]
    client_2.append events_by_aggregate_id[AGGREGATE_ID_TWO]
  end

  it "counts the number of aggregates or clients" do
    expect(es_client.count).to eql(2)
  end

  it "returns a partial list of aggregates" do
    offset = 0
    limit = 1
    expect(es_client.ids(offset, limit)).to eq([[AGGREGATE_ID_ONE, AGGREGATE_ID_TWO].sort.first])
  end

  describe '#raw_event_stream' do
    it "should be an array of hashes that represent database records, not EventStore::SerializedEvent objects" do
      raw_stream = es_client.new(AGGREGATE_ID_ONE, :device).raw_event_stream
      expect(raw_stream.class).to eq(Array)
      raw_event = raw_stream.first
      expect(raw_event.class).to eq(Hash)
      expect(raw_event.keys).to eq([:id, :version, :aggregate_id, :fully_qualified_name, :occurred_at, :serialized_event])
    end

    it 'should be empty for aggregates without events' do
      stream = es_client.new(100, :device).raw_event_stream
      expect(stream.empty?).to be_truthy
    end

    it 'should only have events for a single aggregate' do
      stream = es_client.new(AGGREGATE_ID_ONE, :device).raw_event_stream
      stream.each { |event| expect(event[:aggregate_id]).to eq(AGGREGATE_ID_ONE) }
    end

    it 'should have all events for that aggregate' do
      stream = es_client.new(AGGREGATE_ID_ONE, :device).raw_event_stream
      expect(stream.count).to eq(10)
    end
  end

  describe '#event_stream' do
    it "should be an array of EventStore::SerializedEvent objects" do
      stream = es_client.new(AGGREGATE_ID_ONE, :device).event_stream
      expect(stream.class).to eq(Array)
      event = stream.first
      expect(event.class).to eq(EventStore::SerializedEvent)
    end

    it 'should be empty for aggregates without events' do
      stream = es_client.new(100, :device).raw_event_stream
      expect(stream.empty?).to be_truthy
    end

    it 'should only have events for a single aggregate' do
      raw_stream = es_client.new(AGGREGATE_ID_ONE, :device).raw_event_stream
      stream = es_client.new(AGGREGATE_ID_ONE, :device).event_stream
      expect(stream.map(&:fully_qualified_name)).to eq(raw_stream.inject([]){|m, event| m << event[:fully_qualified_name]; m})
    end

    it 'should have all events for that aggregate' do
      stream = es_client.new(AGGREGATE_ID_ONE, :device).event_stream
      expect(stream.count).to eq(10)
    end

    context "when the serialized event is terminated prematurely with a null byte" do
      it "does not truncate the serialized event when there is a binary zero value is at the end" do
        serialized_event = serialized_event_data_terminated_by_null
        client = es_client.new("any_device", :device)
        event = EventStore::Event.new("any_device", @event_time, 'other_event_name', serialized_event, client.version + 1)
        client.append([event])
        expect(client.event_stream.last[:serialized_event]).to eql(serialized_event)
      end

      it "conversion of byte array to and from hex should be lossless" do
        client = es_client.new("any_device", :device)
        serialized_event = serialized_event_data_terminated_by_null
        event = EventStore::Event.new("any_device", @event_time, 'terminated_by_null_event', serialized_event, client.version + 1)
        client.append([event])
        hex_from_db = EventStore.db.from(EventStore.fully_qualified_table).where(fully_qualified_name: 'terminated_by_null_event').first[:serialized_event]
        expect(hex_from_db).to eql(EventStore.escape_bytea(serialized_event))
      end
    end
  end


  describe '#raw_event_streams_from_version' do
    subject { es_client.new(AGGREGATE_ID_ONE, :device) }

    it 'should return all the raw events in the stream starting from a certain version' do
      minimum_event_version = 2
      raw_stream = subject.raw_event_stream_from(minimum_event_version)
      event_versions = raw_stream.inject([]){|m, event| m << event[:version]; m}
      expect(event_versions.min).to be >= minimum_event_version
    end

    it 'should return no more than the maximum number of events specified above the ' do
      max_number_of_events  = 5
      minimum_event_version = 2
      raw_stream = subject.raw_event_stream_from(minimum_event_version, max_number_of_events)
      expect(raw_stream.count).to eq(max_number_of_events)
    end

    it 'should be empty for version above the current highest version number' do
      raw_stream = subject.raw_event_stream_from(subject.version + 1)
      expect(raw_stream).to be_empty
    end
  end

  describe 'event_stream_from_version' do
    subject { es_client.new(AGGREGATE_ID_ONE, :device) }

    it 'should return all the raw events in the stream starting from a certain version' do
      minimum_event_version = 2
      raw_stream = subject.raw_event_stream_from(minimum_event_version)
      event_versions = raw_stream.inject([]){|m, event| m << event[:version]; m}
      expect(event_versions.min).to be >= minimum_event_version
    end

    it 'should return no more than the maximum number of events specified above the ' do
      max_number_of_events  = 5
      minimum_event_version = 2
      raw_stream = subject.raw_event_stream_from(minimum_event_version, max_number_of_events)
      expect(raw_stream.count).to eq(max_number_of_events)
    end

    it 'should be empty for version above the current highest version number' do
      raw_stream = subject.raw_event_stream_from(subject.version + 1)
      expect(raw_stream).to eq([])
    end
  end

  describe '#event_stream_between' do
    subject {es_client.new(AGGREGATE_ID_ONE, :device)}

    before do
      version = subject.version
      @oldest_event_time = @event_time + 1
      @middle_event_time = @event_time + 2
      @newest_event_time = @event_time + 3

      @outside_event = EventStore::Event.new(AGGREGATE_ID_ONE, (@event_time).utc, "middle_event", "#{1002.to_s(2)}_foo", version += 1)
      @event = EventStore::Event.new(AGGREGATE_ID_ONE, (@oldest_event_time).utc, "oldest_event", "#{1002.to_s(2)}_foo", version += 1)
      @new_event = EventStore::Event.new(AGGREGATE_ID_ONE, (@middle_event_time).utc, "middle_event", "#{1002.to_s(2)}_foo", version += 1)
      @newest_event = EventStore::Event.new(AGGREGATE_ID_ONE, (@newest_event_time).utc, "newest_event_type", "#{1002.to_s(2)}_foo", version += 1)
      subject.append([@event, @new_event, @newest_event])
    end

    it "returns all events between a start and an end time" do
      start_time = @oldest_event_time
      end_time   = @newest_event_time
      expect(subject.event_stream_between(start_time, end_time).length).to eq(3)
    end

    it "returns an empty array if start time is before end time" do
      start_time = @newest_event_time
      end_time   = @oldest_event_time
      expect(subject.event_stream_between(start_time, end_time).length).to eq(0)
    end

    it "returns all the events at a given time if the start time is the same as the end time" do
      start_time = @oldest_event_time
      end_time   = @oldest_event_time
      expect(subject.event_stream_between(start_time, end_time).length).to eq(1)
    end

    it "returns unencodes the serialized_event fields out of the database encoding" do
      expect(EventStore).to receive(:unescape_bytea).once
      start_time = @oldest_event_time
      end_time   = @oldest_event_time
      expect(subject.event_stream_between(start_time, end_time).length).to eq(1)
    end

    it "returns the raw events translated into SerializedEvents" do
      expect(subject).to receive(:translate_events).once.and_call_original
      start_time = @oldest_event_time
      end_time   = @oldest_event_time
      expect(subject.event_stream_between(start_time, end_time).length).to eq(1)
    end

    it "returns types requested within the time range" do
      start_time = @oldest_event_time
      end_time   = @newest_event_time
      fully_qualified_name = 'middle_event'
      expect(subject.event_stream_between(start_time, end_time, [fully_qualified_name]).length).to eq(1)
    end

    it "returns types requested within the time range for more than one type" do
      start_time = @oldest_event_time
      end_time   = @newest_event_time
      fully_qualified_names = ['middle_event', 'newest_event_type']
      expect(subject.event_stream_between(start_time, end_time, fully_qualified_names).length).to eq(2)
    end

    it "returns an empty array if there are no events of the requested types in the time range" do
      start_time = @oldest_event_time
      end_time   = @newest_event_time
      fully_qualified_names = ['random_strings']
      expect(subject.event_stream_between(start_time, end_time, fully_qualified_names).length).to eq(0)
    end

    it "returns only events of types that exist within the time range" do
      start_time = @oldest_event_time
      end_time   = @newest_event_time
      fully_qualified_names = ['middle_event', 'event_name']
      expect(subject.event_stream_between(start_time, end_time, fully_qualified_names).length).to eq(1)
    end
  end

  describe '#peek' do
    let(:client) {es_client.new(AGGREGATE_ID_ONE, :device)}
    subject { client.peek }

    it 'should return the last event in the event stream' do
      last_event = EventStore.db.from(client.event_table).where(aggregate_id: AGGREGATE_ID_ONE).order(:version).last
      expect(subject).to eq(EventStore::SerializedEvent.new(last_event[:fully_qualified_name], EventStore.unescape_bytea(last_event[:serialized_event]), last_event[:version], @event_time))
    end
  end

  describe '#append' do
    before do
      @client = EventStore::Client.new(AGGREGATE_ID_ONE, :device)
      @event = @client.peek
      version = @client.version
      @old_event = EventStore::Event.new(AGGREGATE_ID_ONE, (@event_time - 2000).utc, "old", "#{1000.to_s(2)}_foo", version += 1)
      @new_event = EventStore::Event.new(AGGREGATE_ID_ONE, (@event_time - 1000).utc, "new", "#{1001.to_s(2)}_foo", version += 1)
      @really_new_event = EventStore::Event.new(AGGREGATE_ID_ONE, (@event_time + 100).utc, "really_new", "#{1002.to_s(2)}_foo", version += 1)
      @duplicate_event  = EventStore::Event.new(AGGREGATE_ID_ONE, (@event_time).utc, 'duplicate', "#{12.to_s(2)}_foo", version += 1)
    end

    describe "when expected version number is greater than the last version" do
      describe 'and there are no prior events of type' do
        before do
          @client.append([@old_event])
        end

        it 'should append a single event of a new type without raising an error' do
          initial_count = @client.count
          events = [@new_event]
          @client.append(events)
          expect(@client.count).to eq(initial_count + events.length)
        end

        it 'should append multiple events of a new type without raising and error' do
          initial_count = @client.count
          events = [@new_event, @new_event]
          @client.append(events)
          expect(@client.count).to eq(initial_count + events.length)
        end

        it "should increment the version number by the number of events added" do
          events = [@new_event, @really_new_event]
          initial_version = @client.version
          @client.append(events)
          expect(@client.version).to eq(initial_version + events.length)
        end

        it "should set the snapshot version number to match that of the last event in the aggregate's event stream" do
          events = [@new_event, @really_new_event]
          initial_stream_version = @client.raw_event_stream.last[:version]
          expect(@client.snapshot.last.version).to eq(initial_stream_version)
          @client.append(events)
          updated_stream_version = @client.raw_event_stream.last[:version]
          expect(@client.snapshot.last.version).to eq(updated_stream_version)
        end

        it "should write-through-cache the event in a snapshot without duplicating events" do
          @client.destroy!
          @client.append([@old_event, @new_event, @really_new_event])
          expect(@client.snapshot).to eq(@client.event_stream)
        end

        it "should raise a meaningful exception when a nil event given to it to append" do
          expect {@client.append([nil])}.to raise_exception(ArgumentError)
        end
      end

      describe 'with prior events of same type' do
        it 'should raise a ConcurrencyError if the the event version is less than current version' do
          @client.append([@duplicate_event])
          reset_current_version_for(@client)
          expect { @client.append([@duplicate_event]) }.to raise_error(EventStore::ConcurrencyError)
        end

        it 'should not raise an error when two events of the same type are appended' do
          @client.append([@duplicate_event])
          @duplicate_event[:version] += 1
          @client.append([@duplicate_event]) #will fail automatically if it throws an error, no need for assertions (which now print warning for some reason)
        end

        it "should write-through-cache the event in a snapshot without duplicating events" do
          @client.destroy!
          @client.append([@old_event, @new_event, @new_event])
          expected =  []
          expected << @client.event_stream.first
          expected << @client.event_stream.last
          expect(@client.snapshot).to eq(expected)
        end

        it "should increment the version number by the number of unique events added" do
          events = [@old_event, @old_event, @old_event]
          initial_version = @client.version
          @client.append(events)
          expect(@client.version).to eq(initial_version + events.uniq.length)
        end

        it "should set the snapshot version number to match that of the last event in the aggregate's event stream" do
          events = [@old_event, @old_event]
          initial_stream_version = @client.raw_event_stream.last[:version]
          expect(@client.snapshot.last.version).to eq(initial_stream_version)
          @client.append(events)
          updated_stream_version = @client.raw_event_stream.last[:version]
          expect(@client.snapshot.last.version).to eq(updated_stream_version)
        end
      end
    end

    describe 'transactional' do
      before do
        @bad_event = @new_event.dup
        @bad_event.fully_qualified_name = nil
      end

      it 'should revert all append events if one fails' do
        starting_count = @client.count
        expect { @client.append([@new_event, @bad_event]) }.to raise_error(EventStore::AttributeMissingError)
        expect(@client.count).to eq(starting_count)
      end

      it 'does not yield to the block if it fails' do
        x = 0
        expect { @client.append([@bad_event]) { x += 1 } }.to raise_error(EventStore::AttributeMissingError)
        expect(x).to eq(0)
      end

      it 'yield to the block after event creation' do
        x = 0
        @client.append([]) { x += 1 }
        expect(x).to eq(1)
      end

      it 'should pass the raw event_data to the block' do
        @client.append([@new_event]) do |raw_event_data|
          expect(raw_event_data).to eq([@new_event])
        end
      end
    end

    describe 'snapshot' do
      before do
        @client = es_client.new(AGGREGATE_ID_THREE, :device)
        expect(@client.snapshot.length).to eq(0)
        version = @client.version
        @client.append %w{ e1 e2 e3 e1 e2 e4 e5 e2 e5 e4}.map {|fqn|EventStore::Event.new(AGGREGATE_ID_THREE, Time.now.utc, fqn, serialized_binary_event_data, version += 1)}
      end

      it "finds the most recent records for each type" do
        version = @client.version
        expected_snapshot = %w{ e1 e2 e3 e4 e5 }.map {|fqn| EventStore::SerializedEvent.new(fqn, serialized_binary_event_data, version +=1 ) }
        actual_snapshot = @client.snapshot
        expect(@client.event_stream.length).to eq(10)
        expect(actual_snapshot.length).to eq(5)
        expect(actual_snapshot.map(&:fully_qualified_name)).to eq(["e3", "e1", "e2", "e5", "e4"]) #sorted by version no
        expect(actual_snapshot.map(&:serialized_event)).to eq(expected_snapshot.map(&:serialized_event))
        most_recent_events_of_each_type = {}
        @client.event_stream.each do |e|
          if most_recent_events_of_each_type[e.fully_qualified_name].nil? || most_recent_events_of_each_type[e.fully_qualified_name].version < e.version
            most_recent_events_of_each_type[e.fully_qualified_name] = e
          end
        end
        expect(actual_snapshot.map(&:version)).to eq(most_recent_events_of_each_type.values.map(&:version).sort)
      end

      it "increments the version number of the snapshot when an event is appended" do
        expect(@client.snapshot.last.version).to eq(@client.raw_event_stream.last[:version])
      end
    end


    def reset_current_version_for(client)
      aggregate = client.instance_variable_get("@aggregate")
      EventStore.redis.hset(aggregate.snapshot_version_table, :current_version, 1000)
    end

  end
  def serialized_event_data_terminated_by_null
    @term_data ||= File.open(File.expand_path("../binary_string_term_with_null_byte.txt", __FILE__), 'rb') {|f| f.read}
    @term_data
  end
  def serialized_binary_event_data
    @event_data ||= File.open(File.expand_path("../serialized_binary_event_data.txt", __FILE__), 'rb') {|f| f.read}
    @event_data
  end
end
