require 'active_support/core_ext/module/attr_internal'
require 'logical_record/log_subscriber'

module LogicalRecord
  module Railties
    module ControllerRuntime #:nodoc:
      extend ActiveSupport::Concern

    protected

      attr_internal :db_runtime

      def process_action(action, *args)
        # We also need to reset the runtime before each action
        # because of queries in middleware or in cases we are streaming
        # and it won't be cleaned up by the method below.
        LogicalRecord::LogSubscriber.reset_runtime
        super
      end

      def cleanup_view_runtime
        if LogicalRecord::Base.connected?
          db_rt_before_render = LogicalRecord::LogSubscriber.reset_runtime
          runtime = super
          db_rt_after_render = LogicalRecord::LogSubscriber.reset_runtime
          self.db_runtime = db_rt_before_render + db_rt_after_render
          runtime - db_rt_after_render
        else
          super
        end
      end

      def append_info_to_payload(payload)
        super
        if LogicalRecord::Base.connected?
          payload[:db_runtime] = (db_runtime || 0) + LogicalRecord::LogSubscriber.reset_runtime
        end
      end

      module ClassMethods
        def log_process_action(payload)
          messages, db_runtime = super, payload[:db_runtime]
          messages << ("LogicalRecord: %.1fms" % db_runtime.to_f) if db_runtime
          messages
        end
      end
    end
  end
end