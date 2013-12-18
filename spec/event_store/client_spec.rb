require_relative '../spec_helper'

# Forgive me
def set_expected_version version_number
  EventStore::EventAppender.class_eval(
    %Q(alias_method :old_expected_version, :expected_version;
      def expected_version; #{version_number}; end)
  )
end

def reset_expected_version
  EventStore::EventAppender.class_eval("alias_method :expected_version, :old_expected_version")
end

def with_expected_version version_number
  set_expected_version version_number
  yield
  reset_expected_version
end

describe EventStore::Client do
  before do
    agg = EventStore::Aggregate.new(1, :device)
    ([1]*10 + [2]*10).shuffle.each do |aggregate_id|
      agg.events.insert :aggregate_id => aggregate_id, :occurred_at => DateTime.now, :data => 234532.to_s(2), :fully_qualified_name => 'event_name'
    end
  end

  let(:es_client) { EventStore::Client }

  describe 'event streams' do
    it 'should be empty for aggregates without events' do
      stream = es_client.new(100, :device).event_stream
      expect(stream.empty?).to be_true
    end

    it 'should be for a single aggregate' do
      stream = es_client.new(1, :device).event_stream
      expect(stream.map(&:aggregate_id).all?{ |aggregate_id| aggregate_id == '1' }).to be_true
    end

    it 'should include all events for that aggregate' do
      stream = es_client.new(1, :device).event_stream
      expect(stream.count).to eq(10)
    end
  end


  describe 'event streams from version' do
    subject { es_client.new(1, :device) }

    it 'should respect the max, if specified' do
      stream = subject.event_stream_from(2, 5)
      expect(stream.count).to eq(5)
    end

    it 'should be empty for version above the current highest version number' do
      stream = subject.event_stream_from(123456)
      expect(stream).to be_empty
    end
  end

  describe '#peek' do
    subject { es_client.new(1, :device).peek }

    it 'should return the last event in the event stream' do
      last_event = EventStore.db.from(:device_events).where(aggregate_id: '1').order(:version).last
      expect(subject).to eq(EventStore::Event.new(last_event[:aggregate_id], last_event[:occurred_at], last_event[:data], last_event[:fully_qualified_name]))
    end
  end

  describe '#append' do
    before do
      @client = EventStore::Client.new(1, :device)
      @event = @client.peek
      @new_event = EventStore::Event.new('1', DateTime.now, "new", 1001.to_s(2))
    end

    describe "expected version number < last version" do
      describe 'type mismatch' do
        it 'should raise an error' do
          @client.instance_variable_get('@aggregate').events.insert(:fully_qualified_name => 'duplicate', :aggregate_id => 1, :occurred_at => DateTime.now, :data => 12.to_s(2))
          @new_event.fully_qualified_name = "duplicate"
          with_expected_version(0) do
            expect { @client.append([@new_event]) }.to raise_error(EventStore::ConcurrencyError)
          end
        end
      end

      describe 'no prior events of type' do
        before do
          @client.instance_variable_get('@aggregate').events.insert(:fully_qualified_name => 'old', :aggregate_id => 1, :occurred_at => DateTime.now, :data => 12.to_s(2))
        end

        it 'should succeed' do
          expect(@client.append([@new_event])).to be_nil
        end

        it 'should succeed with multiple events of the same type' do
          expect(@client.append([@new_event, @new_event])).to be_nil
        end
      end

      describe 'with prior events of same type' do
        it 'should raise an error' do
          @client.append([@new_event])
          with_expected_version(0) do
            expect { @client.append([@new_event]) }.to raise_error(EventStore::ConcurrencyError)
          end
        end
      end
    end

    describe 'transactional' do
      before do
        @bad_event = @new_event.dup
        @bad_event.fully_qualified_name = nil
      end

      it 'should revert all append events if one fails' do
        starting_count = EventStore.db.from(:device_events).count
        expect { @client.append([@new_event, @bad_event]) }.to raise_error(EventStore::AttributeMissingError)
        expect(EventStore.db.from(:device_events).count).to eq(starting_count)
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
  end

  describe 'current_state' do
    it "finds the most recent records for each type" do
      aggregate = EventStore::Aggregate.new(10, :device)
      %w{ e1 e2 e3 e1 }.each do |fqn|
        aggregate.events.insert :aggregate_id => 10, :occurred_at => DateTime.now, :data => 234532.to_s(2), :fully_qualified_name => fqn
      end
      events_we_expect = %w{ e1 e2 e3 e4 e5 }.map do |fqn|
        aggregate.events.insert :aggregate_id => 10, :occurred_at => DateTime.now, :data => 234532.to_s(2), :fully_qualified_name => fqn
        last_event = aggregate.events.last
        EventStore::Event.new(last_event[:aggregate_id], last_event[:occurred_at], last_event[:data], last_event[:fully_qualified_name])
      end
      expect(es_client.new(10, :device).current_state).to match_array(events_we_expect)
    end
  end

end
