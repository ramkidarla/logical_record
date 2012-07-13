module LogicalRecord
  module Associations
    class JoinDependency # :nodoc:
      class JoinBase < JoinPart # :nodoc:
        def ==(other)
          other.class == self.class &&
            other.logical_record == logical_record
        end

        def aliased_prefix
          "t0"
        end

        def table
          Arel::Table.new(table_name, arel_engine)
        end

        def aliased_table_name
          logical_record.table_name
        end
      end
    end
  end
end
