module LogicalRecord
  module Associations
    class Preloader
      class HasMany < CollectionAssociation #:nodoc:

        def association_key_name
          reflection.foreign_key
        end

        def owner_key_name
          reflection.logical_record_primary_key
        end

      end
    end
  end
end
