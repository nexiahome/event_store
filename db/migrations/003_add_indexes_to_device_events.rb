Sequel.migration do
  change do
    add_index :device_events, :aggregate_id
    add_index :device_events, :fully_qualified_name
  end
end
