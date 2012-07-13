require 'logical_record/connection_adapters/abstract/database_statements'
require 'arel/visitors/bind_visitor'

require 'timeout'
require 'typhoeus'
require 'logger'
require 'kaminari'


module LogicalRecord
  class Base
    
    attr_accessor :ws_errors
    
    # restfull json adapter
    def self.restfull_json_connection(config) # :nodoc:
      config = config.symbolize_keys
      ConnectionAdapters::RestfullJsonAdapter.new(config, logger)
    end
  end
  
  
  module ConnectionAdapters #:nodoc:
    class RestfullJsonColumn < Column #:nodoc:
      class << self
        def binary_to_string(value)
          if value.encoding != Encoding::ASCII_8BIT
            value = value.force_encoding(Encoding::ASCII_8BIT)
          end
          value
        end
      end
    end

    # The Restfull adapter works Restfull JSON format
    
    # Options:
    #
    # * <tt>:database</tt> - Path to the database file.
    class RestfullJsonAdapter < AbstractAdapter
      attr_accessor :last_insert_row_id
      
      def timeout; @timeout ||= DEFAULT_TIMEOUT; end
      def use_ssl; @use_ssl ||= false; end
      def log_path; @log_path ||= "log/logical_model.log"; end
      def use_api_key; @use_api_key ||= false; end
      def delete_multiple_enabled?; @enable_delete_multiple ||= false; end
      
      
      DEFAULT_TIMEOUT = 10000
      
      def json_root
        @json_root ||= self.class.to_s.underscore
      end
      
      def resource_uri(action = nil)
        prefix = (use_ssl)? "https://" : "http://"
        sufix = (action.nil?)? "" : "/#{action}"
        "#{prefix}#{host}#{resource_path}#{sufix}"
      end
      
    
      ADAPTER_NAME = 'RestfullJson'
      
      #NATIVE_DATABASE_TYPES = {
      #    :primary_key => 'INTEGER PRIMARY KEY NOT NULL',
      #    :string => { :name => "string" },
      #    :integer => { :name => "integer" },
      #    :float => { :name => "float" },
      #    :decimal => { :name => "decimal" },
      #    :datetime => { :name => "datetime" },
      #    :timestamp => { :name => "datetime" },
      #    :time => { :name => "datetime" },
      #    :date => { :name => "date" },
      #    :binary => { :name => "blob" },
      #    :boolean => { :name => "boolean" }
      #}
      def adapter_name
        ADAPTER_NAME
      end
      
      
      class BindSubstitution <  Arel::Visitors::ToSql
        include Arel::Visitors::BindVisitor
      end
      
      def initialize(config, logger)
        super(config, logger)
        
        @instrumenter = ActiveSupport::Notifications.instrumenter
        
        @config = config
        @visitor = BindSubstitution.new self
      end
      
      # Returns true since this connection adapter supports savepoints
      def supports_savepoints?
        true
      end

      # Returns true.
      def supports_primary_key? #:nodoc:
        true
      end

      # Disconnects from the database if already connected. Otherwise, this
      # method does nothing.
      def disconnect!
        super  
        clear_cache!
        #@connection.close rescue nil
        @connection = nil
      end

      # Clears the prepared statements cache.
      def clear_cache!
        
      end

      # Returns true
      def supports_count_distinct? #:nodoc:
        true
      end
      
      #def native_database_types #:nodoc:
       # NATIVE_DATABASE_TYPES
      #end

      # Returns the current database encoding format as a string, eg: 'UTF-8'
      def encoding
        #@connection.encoding.to_s
        'UTF-8'
      end

      # Returns true.
      def supports_explain?
        true
      end

      # QUOTING ==================================================

      def quote(value, column = nil)
        if value.kind_of?(String) && column && column.type == :binary && column.class.respond_to?(:string_to_binary)
          s = column.class.string_to_binary(value).unpack("H*")[0]
          "x'#{s}'"
        else
          super
        end
      end

      def quote_string(s) #:nodoc:
        s.gsub(/\\/, '\&\&').gsub(/'/, "''") # ' (for ruby-mode)
      end

      def quote_column_name(name) #:nodoc:
        name
        #%Q("#{name.to_s.gsub('"', '""')}")
      end

      # Quote date/time values for use in SQL input. Includes microseconds
      # if the value is a Time responding to usec.
      def quoted_date(value) #:nodoc:
        if value.respond_to?(:usec)
          "#{super}.#{sprintf("%06d", value.usec)}"
        else
          super
        end
      end

      def type_cast(value, column) # :nodoc:
        return value.to_f if BigDecimal === value
        return super unless String === value
        return super unless column && value

        value = super
        if column.type == :string && value.encoding == Encoding::ASCII_8BIT
          logger.error "Binary data inserted for `string` type on column `#{column.name}`" if logger
          value.encode! 'utf-8'
        end
        value
      end

      # Restfull web service calls ======================================
      def exec_invoke_call(action, attributes_with_values = {}, body = nil, headers = nil, name = nil, binds = [])
        record.ws_errors = {}
        result = post_ws(resource_uri(action), {}.merge({:attributes => attributes_with_values}), body, headers)
        
        raise WsRecordInvalid.new(record) if record.ws_errors.present? 
        
        json_parsed_record(result) if result.present?
      end
      
      def exec_select_call(sql, name = nil, binds = [])
        log(sql, name, binds) do
           # Don't cache statements without bind values
          if binds.empty?
            result = post_ws(resource_uri('select'), {:sql => sql})
          else
             #get it from cache
            result = post_ws(resource_uri('select'), {:sql => sql})
          end
          json_parsed_record(result)
        end
      end
      
      def exec_insert_call(id, attributes_with_values = {}, name = nil, binds = [])
        record.ws_errors = {}
        result = post_ws(resource_uri(), {}.merge({:attributes => attributes_with_values}))
        
        raise WsRecordInvalid.new(record) if record.ws_errors.present? 
        
        obj = json_parsed_record(result) if result.present?
        @last_insert_row_id = obj.to_hash.first['id'] if obj.present?
        #log(sql, name, binds) do
        #end
      end
      
      def exec_delete_call(id, name = nil, binds = [])
        record.ws_errors = {}
        delete_ws(resource_uri(id))
        raise WsRecordInvalid.new(record) if record.ws_errors.present? 
        #log(sql, name, binds) do
        #end
      end
      
      def exec_update_call(id, attributes_with_values = {}, name = nil, binds = [])
        
        record.ws_errors = {}
        result = put_easy_ws(resource_uri(id), {}.merge({:attributes => attributes_with_values}))
        raise WsRecordInvalid.new(record) if record.ws_errors.present? 
        
        rows_affected = 1
        #log(sql, name, binds) do
        #end
      end
      
      def valid_call?(id, attributes_with_values = {})
        record.ws_errors = {}
        result = post_ws(resource_uri('valid'), {}.merge({:id => id, :attributes => attributes_with_values}))
        
        raise WsRecordInvalid.new(record) if record.ws_errors.present? 
        true
      end
      
      def last_inserted_id(result)
        last_insert_row_id
      end
      
      #def update_sql(sql, name = nil) #:nodoc:
      #  puts "update_sql:sql:#{sql}"
      #  super
        #@connection.changes
      #end

      #def delete_sql(sql, name = nil) #:nodoc:
      #  sql += " WHERE 1=1" unless sql =~ /WHERE/i
      #  puts "delete_sql:sql:#{sql}"
      #  super sql, name
      #end

      #def insert_sql(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil) #:nodoc:
      #  puts "insert_sql:sql:#{sql}"
      #  super
      #  id_value || @connection.last_insert_row_id
      #end
      #alias :create :insert_sql

      def select_rows(sql, name = nil)
        exec_select_call(sql, name).rows
      end

      # SCHEMA STATEMENTS ========================================

      def table_exists?(table_name)
        true
      end

      # Returns an array of +RestfullJsonColumn+ objects for the table specified by +table_name+.
      def columns(table_name, name = nil) #:nodoc:
        table_fields(table_name).map do |field|
          RestfullJsonColumn.new(field[:name], field[:default], field[:type], field[:null] == true)
        end
      end

      def primary_key(table_name) #:nodoc:
        column = table_fields(table_name).find { |field|
          field[:primary] == true
        }
        column && column[:name]
      end
      
      def table_fields(table_name)
        result = get_ws(resource_uri('schema_fields'))
        
        fields = []
        JSON.parse(result).each do |field|
          fields << ActiveSupport::JSON.decode(field).symbolize_keys
        end
        fields
      end
      
      protected
        def select(sql, name = nil, binds = []) #:nodoc:
          exec_select_call(sql, name, binds)
        end

        def translate_exception(exception, message)
          case exception.message
          when /column(s)? .* (is|are) not unique/
            RecordNotUnique.new(message, exception)
          else
            super
          end
        end
        
       private
        
        def log_ws_200(res)
          @logger.debug res if @logger
          logicallogger.info("LogicalRecord Log 200: #{res}")
        end
        
        def log_ws_400(res)
          @logger.debug res if @logger
          logicallogger.info("LogicalRecord Log 400: #{res}")
        end
        
        def log_ws_failed(response)
          begin
            if response.body.present?
              error_message = ActiveSupport::JSON.decode(response.body)["message"]
            else
              error_message = ActiveSupport::JSON.decode(response)["message"]
            end
          rescue => e
            error_message = "error"
          end
          message = "LogicalRecord Log Failed: #{response.code} #{response.request.url} in #{response.time}s FAILED: #{error_message}"
            
          logicallogger.warn("LogicalRecord Log: #{message}")
          logicallogger.debug("LogicalRecord Log: #{response.body}") if response.body.present?
          @logger.debug message if @logger
          exception = LogicalRecord::StatementInvalid.new(message)
          exception.set_backtrace e.backtrace if e.present?
          raise exception
        end
          
        def log_easy_ws_failed(easy)
          begin
            if easy.response_body.present?
              error_message = ActiveSupport::JSON.decode(easy.response_body)["message"]
            else
              error_message = easy
            end
          rescue => e
            error_message = "error"
          end
          message = "LogicalRecord Log Failed: #{easy.response_code} #{easy.url} in #{easy.total_time_taken}s FAILED: #{error_message}"
         
          logicallogger.warn("LogicalRecord Log: #{message}")
          logicallogger.debug("LogicalRecord Log: #{message}")
          @logger.debug message if @logger
          exception = LogicalRecord::StatementInvalid.new(message)
          exception.set_backtrace e.backtrace if e.present?
          raise exception
        end
        
        def json_parsed_record(json_string)
          return nil if !json_string.present?
  
          objParsed = JSON.parse(json_string)
          objArray = objParsed.kind_of?(Hash) ?  [objParsed] : objParsed
  
          fields = []
          values = []
          objArray.each do |obj|
            key_values = []
            obj.each do |key, value|
              if !fields.include?(key)
              fields << key
              end
              key_values << value
            end
            values << key_values.flatten
          end
          LogicalRecord::Result.new(fields, values)
        end
        
        def json_parsed_errors(json_string)
          return nil if !json_string.present?
          wsErrors = ActiveSupport::JSON.decode(json_string)
          if wsErrors.present?
            wsErrors.each_key do |k|
              if wsErrors[k].is_a?(Array)
                record.ws_errors[k] = []
                wsErrors[k].map { |msg| record.ws_errors[k] << msg }
              else
                record.ws_errors[k] = []
                record.ws_errors[k] << wsErrors[k]
              end
            end
          end
        end
        
        def post_ws(url, params = {}, body = nil, headers = nil)
          params = params.merge({api_key_name.to_sym => api_key}) if use_api_key
  
          response = nil
          Timeout::timeout(timeout/1000) do
            if body.nil?
              response = Typhoeus::Request.post( url, :params => params, :timeout => timeout )
            else
              response = Typhoeus::Request.post( url, :body => body, :headers => headers, :timeout => timeout )
            end
          end
          if response.code == 200
            if response.body.present?
              log_ws_200(response.body)
              return response.body
            end
          elsif response.code == 400
            if response.body.present?
              log_ws_400(response.body)
              json_parsed_errors(response.body)
            end 
          else
            log_ws_failed(response)
          end
          return nil
        end
        
        def _async_get_ws(url, params = {})
          request = Typhoeus::Request.new( url, :params => params )
      
          request.on_complete do |response|
            if response.code >= 200 && response.code < 400
              if response.body.present?
                log_ws_200(response.body)
                (yield response.body)
              end
            elsif response.code == 400
              if response.body.present?
                log_ws_400(response.body)
                json_parsed_errors(response.body)
              end
            else
              log_ws_failed(response)
            end
          end
          self.hydra.queue(request)
        end
  
        def get_ws(url, params = {})
          params = params.merge({api_key_name.to_sym => api_key}) if use_api_key 
                  
          result = nil
          _async_get_ws(url, params){|i| result = i}
          Timeout::timeout(timeout/1000) do
            hydra.run
          end
          result
        rescue Timeout::Error
          log_ws_200("timeout")
          return nil
        end
        
        def put_easy_ws(url, params = {})
          params = params.merge({api_key_name.to_sym => api_key}) if use_api_key
          
          # Typhoeus::Easy avoids PUT hang issue: https://github.com/dbalatero/typhoeus/issues/69
          easy = Typhoeus::Easy.new
          easy.url = url
          easy.method = :put
          easy.params = params
          
          Timeout::timeout(timeout/1000) do
            easy.perform
          end
          
          if easy.response_code == 200
            if easy.response_body.present?
              log_ws_200(easy.response_body)
              return easy.response_body
            end
          elsif easy.response_code == 400
            if easy.response_body.present?
              log_ws_400(easy.response_body)
              json_parsed_errors(easy.response_body)
            end
          else
            log_easy_ws_failed(easy)
          end
          return nil
        end
        
        def put_ws(url, params = {})
          params = params.merge({api_key_name.to_sym => api_key}) if use_api_key
          
          response = nil
          Timeout::timeout(timeout/1000) do
            response = Typhoeus::Request.put( url, :params => params, :timeout => timeout )
          end
          if response.code == 200
            if response.body.present?
              log_ws_200(response.body)
              return response.body
            end
          elsif response.code == 400
            if response.body.present?
              log_ws_400(response.body)
              json_parsed_errors(response.body)
            end
          else
            log_ws_failed(response)
          end
          return nil
        end
        
        
        def delete_ws(url, params = {})
          params = params.merge({api_key_name.to_sym => api_key}) if use_api_key
          
          response = nil
          Timeout::timeout(timeout/1000) do
            response = Typhoeus::Request.delete( url, :params => params, :timeout => timeout )
          end
          if response.code == 200
            if response.body.present?
              log_ws_200(response.body)
              return response.body
            end
          elsif response.code == 400
            if response.body.present?
              log_ws_400(response.body)
              json_parsed_errors(response.body)
            end
          else
            log_ws_failed(response)
          end
          return nil
        end 
        
    end
  end
end