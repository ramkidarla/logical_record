module LogicalRecord
  module Associations
    class Preloader
      class HasOneThrough < SingularAssociation #:nodoc:
        include ThroughAssociation
      end
    end
  end
end
