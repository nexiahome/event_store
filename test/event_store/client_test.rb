require_relative '../minitest_helper'

# run once setup
([1]*10 + [2]*10).shuffle.each do |device_id|
  event = EventStore::Event.new :device_id => device_id
  event.stub :validate, true do
    event.save
  end
end


describe EventStore::Client do
  before { @es_client = EventStore::Client }

  describe 'event streams' do
    it 'should be empty for devices without events' do
      stream = @es_client.new(100).event_stream
      assert stream.empty?
    end

    it 'should be for a single device' do
      stream = @es_client.new(1).event_stream
      assert stream.map(&:device_id).all?{ |device_id| device_id == '1' }, 'Fetched multiple device_ids in the event stream'
    end

    it 'should include all events for that device' do
      stream = @es_client.new(1).event_stream
      assert_equal 10, stream.count
    end
  end


  describe 'event streams from sequence' do
    subject { @es_client.new(1) }

    it 'should return events starting at the specified sequence number and above' do
      stream = subject.event_stream_from(2)
      assert stream.map(&:sequence_number).all?{ |sequence_number| sequence_number >= 2 }, 'Fetched sequence numbers below the specified sequence number'
    end

    it 'should respect the max, if specified' do
      stream = subject.event_stream_from(2, 5)
      assert_equal 5, stream.count
    end

    it 'should be empty for sequences above the current highest sequence number' do
      stream = subject.event_stream_from(43)
      assert stream.empty?
    end
  end

  describe '#peek' do
    subject { @es_client.new(1).peek }

    it 'should return one event' do
      assert_equal EventStore::Event, subject.class
    end

    it 'should return the last event in the event stream' do
      last_event = Sequel::Model.db.from(:event_store_events).where(device_id: 1).order(:sequence_number).last
      assert_equal last_event[:sequence_number], subject.sequence_number
    end
  end

  describe '#append' do
    it 'should raise if the expected_sequence_number is before the last_sequence_number' do
      skip "needs clarification"
    end

    it 'create the events' do
      skip "needs clarification"
    end

    it 'yield to the block after event creation' do
      skip "needs clarification"
    end

    it 'is run in a transaction' do
      skip "put in two events, one valid one invalid, and assert that neither are persisted"
    end
  end

end
