LogicalRecord::Base.connection.increment_open_transactions
LogicalRecord::Base.connection.begin_db_transaction
at_exit do
  LogicalRecord::Base.connection.rollback_db_transaction
  LogicalRecord::Base.connection.decrement_open_transactions
end
