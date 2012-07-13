require 'active_support/concern'

module LogicalRecord
  # = Active Record Persistence
  module Persistence
    extend ActiveSupport::Concern

    module ClassMethods
      # Creates an object (or multiple objects) and saves it to the database, if validations pass.
      # The resulting object is returned whether the object was saved successfully to the database or not.
      #
      # The +attributes+ parameter can be either be a Hash or an Array of Hashes. These Hashes describe the
      # attributes on the objects that are to be created.
      #
      # +create+ respects mass-assignment security and accepts either +:as+ or +:without_protection+ options
      # in the +options+ parameter.
      #
      # ==== Examples
      #   # Create a single new object
      #   User.create(:first_name => 'Jamie')
      #
      #   # Create a single new object using the :admin mass-assignment security role
      #   User.create({ :first_name => 'Jamie', :is_admin => true }, :as => :admin)
      #
      #   # Create a single new object bypassing mass-assignment security
      #   User.create({ :first_name => 'Jamie', :is_admin => true }, :without_protection => true)
      #
      #   # Create an Array of new objects
      #   User.create([{ :first_name => 'Jamie' }, { :first_name => 'Jeremy' }])
      #
      #   # Create a single object and pass it into a block to set other attributes.
      #   User.create(:first_name => 'Jamie') do |u|
      #     u.is_admin = false
      #   end
      #
      #   # Creating an Array of new objects using a block, where the block is executed for each object:
      #   User.create([{ :first_name => 'Jamie' }, { :first_name => 'Jeremy' }]) do |u|
      #     u.is_admin = false
      #   end
      def create(attributes = nil, options = {}, &block)
        if attributes.is_a?(Array)
          attributes.collect { |attr| create(attr, options, &block) }
        else
          object = new(attributes, options, &block)
          object.save
          object
        end
      end
    end

    # Returns true if this object hasn't been saved yet -- that is, a record
    # for the object doesn't exist in the data store yet; otherwise, returns false.
    def new_record?
      @new_record
    end

    # Returns true if this object has been destroyed, otherwise returns false.
    def destroyed?
      @destroyed
    end

    # Returns if the record is persisted, i.e. it's not a new record and it was
    # not destroyed.
    def persisted?
      !(new_record? || destroyed?)
    end

    # Saves the model.
    #
    # If the model is new a record gets created in the database, otherwise
    # the existing record gets updated.
    #
    # By default, save always run validations. If any of them fail the action
    # is cancelled and +save+ returns +false+. However, if you supply
    # :validate => false, validations are bypassed altogether. See
    # LogicalRecord::Validations for more information.
    #
    # There's a series of callbacks associated with +save+. If any of the
    # <tt>before_*</tt> callbacks return +false+ the action is cancelled and
    # +save+ returns +false+. See LogicalRecord::Callbacks for further
    # details.
    def save(*)
      begin
        create_or_update
      rescue LogicalRecord::RecordInvalid
        false
      rescue LogicalRecord::WsRecordInvalid
        add_ws_errors
        false
      end
    end

    # Saves the model.
    #
    # If the model is new a record gets created in the database, otherwise
    # the existing record gets updated.
    #
    # With <tt>save!</tt> validations always run. If any of them fail
    # LogicalRecord::RecordInvalid gets raised. See LogicalRecord::Validations
    # for more information.
    #
    # There's a series of callbacks associated with <tt>save!</tt>. If any of
    # the <tt>before_*</tt> callbacks return +false+ the action is cancelled
    # and <tt>save!</tt> raises LogicalRecord::RecordNotSaved. See
    # LogicalRecord::Callbacks for further details.
    def save!(*)
      begin
        create_or_update || raise(RecordNotSaved)
      rescue LogicalRecord::WsRecordInvalid
        add_ws_errors
        raise(RecordNotSaved)
      end
    end

    # Deletes the record in the database and freezes this instance to
    # reflect that no changes should be made (since they can't be
    # persisted). Returns the frozen instance.
    #
    # The row is simply removed with an SQL +DELETE+ statement on the
    # record's primary key, and no callbacks are executed.
    #
    # To enforce the object's +before_destroy+ and +after_destroy+
    # callbacks, Observer methods, or any <tt>:dependent</tt> association
    # options, use <tt>#destroy</tt>.
    def delete
      if persisted?
        begin
          self.class.delete(id)
          IdentityMap.remove(self) if IdentityMap.enabled?
          clear_ws_errors 
        rescue LogicalRecord::WsRecordInvalid => exception
          self.ws_errors = exception.record.ws_errors
        end
      end
      add_ws_errors
      return self if ws_errors.present?
      
      @destroyed = true
      freeze
    end

    # Deletes the record in the database and freezes this instance to reflect
    # that no changes should be made (since they can't be persisted).
    def destroy
      #destroy_associations

      if persisted?
        IdentityMap.remove(self) if IdentityMap.enabled?
        pk         = self.class.primary_key
        column     = self.class.columns_hash[pk]
        substitute = connection.substitute_at(column, 0)

        relation = self.class.unscoped.where(
          self.class.arel_table[pk].eq(substitute))
        
        begin
          relation.bind_values = [[column, id]]
          relation.delete_all
          clear_ws_errors 
        rescue LogicalRecord::WsRecordInvalid => exception
          self.ws_errors = exception.record.ws_errors
        end
      end
      add_ws_errors
      return self if ws_errors.present?
      
      @destroyed = true
      freeze
    end

    # Returns an instance of the specified +klass+ with the attributes of the
    # current record. This is mostly useful in relation to single-table
    # inheritance structures where you want a subclass to appear as the
    # superclass. This can be used along with record identification in
    # Action Pack to allow, say, <tt>Client < Company</tt> to do something
    # like render <tt>:partial => @client.becomes(Company)</tt> to render that
    # instance using the companies/company partial instead of clients/client.
    #
    # Note: The new instance will share a link to the same attributes as the original class.
    # So any change to the attributes in either instance will affect the other.
    def becomes(klass)
      became = klass.new
      became.instance_variable_set("@attributes", @attributes)
      became.instance_variable_set("@attributes_cache", @attributes_cache)
      became.instance_variable_set("@new_record", new_record?)
      became.instance_variable_set("@destroyed", destroyed?)
      became.instance_variable_set("@errors", errors)
      became.type = klass.name unless self.class.descends_from_logical_record?
      became
    end

    # Updates a single attribute and saves the record.
    # This is especially useful for boolean flags on existing records. Also note that
    #
    # * Validation is skipped.
    # * Callbacks are invoked.
    # * updated_at/updated_on column is updated if that column is available.
    # * Updates all the attributes that are dirty in this object.
    #
    def update_attribute(name, value)
      name = name.to_s
      raise LogicalRecordError, "#{name} is marked as readonly" if self.class.readonly_attributes.include?(name)
      send("#{name}=", value)
      save(:validate => false)
    end

    # Updates a single attribute of an object, without calling save.
    #
    # * Validation is skipped.
    # * Callbacks are skipped.
    # * updated_at/updated_on column is not updated if that column is available.
    #
    # Raises an +LogicalRecordError+ when called on new objects, or when the +name+
    # attribute is marked as readonly.
    def update_column(name, value)
      name = name.to_s
      raise LogicalRecordError, "#{name} is marked as readonly" if self.class.readonly_attributes.include?(name)
      raise LogicalRecordError, "can not update on a new record object" unless persisted?
      raw_write_attribute(name, value)
      result = self.class.update_all({ name => value }, self.class.primary_key => id) == 1
      clear_ws_errors
      result
    rescue LogicalRecord::WsRecordInvalid => exception
      self.ws_errors = exception.record.ws_errors
      add_ws_errors
      false
    end

    # Updates the attributes of the model from the passed-in hash and saves the
    # record, all wrapped in a transaction. If the object is invalid, the saving
    # will fail and false will be returned.
    #
    # When updating model attributes, mass-assignment security protection is respected.
    # If no +:as+ option is supplied then the +:default+ role will be used.
    # If you want to bypass the protection given by +attr_protected+ and
    # +attr_accessible+ then you can do so using the +:without_protection+ option.
    def update_attributes(attributes, options = {})
      # The following transaction covers any possible database side-effects of the
      # attributes assignment. For example, setting the IDs of a child collection.
      with_transaction_returning_status do
        self.assign_attributes(attributes, options)
        save
      end
    end

    # Updates its receiver just like +update_attributes+ but calls <tt>save!</tt> instead
    # of +save+, so an exception is raised if the record is invalid.
    def update_attributes!(attributes, options = {})
      # The following transaction covers any possible database side-effects of the
      # attributes assignment. For example, setting the IDs of a child collection.
      with_transaction_returning_status do
        self.assign_attributes(attributes, options)
        save!
      end
    end

    # Initializes +attribute+ to zero if +nil+ and adds the value passed as +by+ (default is 1).
    # The increment is performed directly on the underlying attribute, no setter is invoked.
    # Only makes sense for number-based attributes. Returns +self+.
    def increment(attribute, by = 1)
      self[attribute] ||= 0
      self[attribute] += by
      self
    end

    # Wrapper around +increment+ that saves the record. This method differs from
    # its non-bang version in that it passes through the attribute setter.
    # Saving is not subjected to validation checks. Returns +true+ if the
    # record could be saved.
    def increment!(attribute, by = 1)
      increment(attribute, by).update_attribute(attribute, self[attribute])
    end

    # Initializes +attribute+ to zero if +nil+ and subtracts the value passed as +by+ (default is 1).
    # The decrement is performed directly on the underlying attribute, no setter is invoked.
    # Only makes sense for number-based attributes. Returns +self+.
    def decrement(attribute, by = 1)
      self[attribute] ||= 0
      self[attribute] -= by
      self
    end

    # Wrapper around +decrement+ that saves the record. This method differs from
    # its non-bang version in that it passes through the attribute setter.
    # Saving is not subjected to validation checks. Returns +true+ if the
    # record could be saved.
    def decrement!(attribute, by = 1)
      decrement(attribute, by).update_attribute(attribute, self[attribute])
    end

    # Assigns to +attribute+ the boolean opposite of <tt>attribute?</tt>. So
    # if the predicate returns +true+ the attribute will become +false+. This
    # method toggles directly the underlying value without calling any setter.
    # Returns +self+.
    def toggle(attribute)
      self[attribute] = !send("#{attribute}?")
      self
    end

    # Wrapper around +toggle+ that saves the record. This method differs from
    # its non-bang version in that it passes through the attribute setter.
    # Saving is not subjected to validation checks. Returns +true+ if the
    # record could be saved.
    def toggle!(attribute)
      toggle(attribute).update_attribute(attribute, self[attribute])
    end

    # Reloads the attributes of this object from the database.
    # The optional options argument is passed to find when reloading so you
    # may do e.g. record.reload(:lock => true) to reload the same record with
    # an exclusive row lock.
    def reload(options = nil)
      clear_aggregation_cache
      clear_association_cache

      IdentityMap.without do
        fresh_object = self.class.unscoped { self.class.find(self.id, options) }
        @attributes.update(fresh_object.instance_variable_get('@attributes'))
      end

      @attributes_cache = {}
      self
    end

    # Saves the record with the updated_at/on attributes set to the current time.
    # Please note that no validation is performed and no callbacks are executed.
    # If an attribute name is passed, that attribute is updated along with
    # updated_at/on attributes.
    #
    #   product.touch               # updates updated_at/on
    #   product.touch(:designed_at) # updates the designed_at attribute and updated_at/on
    #
    # If used along with +belongs_to+ then +touch+ will invoke +touch+ method on associated object.
    #
    #   class Brake < LogicalRecord::Base
    #     belongs_to :car, :touch => true
    #   end
    #
    #   class Car < LogicalRecord::Base
    #     belongs_to :corporation, :touch => true
    #   end
    #
    #   # triggers @brake.car.touch and @brake.car.corporation.touch
    #   @brake.touch
    def touch(name = nil)
      attributes = timestamp_attributes_for_update_in_model
      attributes << name if name
      
      
      unless attributes.empty?
        current_time = current_time_from_proper_timezone
        changes = {}

        attributes.each do |column|
          changes[column.to_s] = write_attribute(column.to_s, current_time)
        end

        changes[self.class.locking_column] = increment_lock if locking_enabled?

        @changed_attributes.except!(*changes.keys)
        primary_key = self.class.primary_key
        
        self.class.connection.record = self
        result = self.class.connection.update(id, changes) == 1
        clear_ws_errors
        result
      end
    rescue LogicalRecord::WsRecordInvalid
      add_ws_errors
      false
    end
    
    #return true if valid otherwise return false
    def ws_valid?
      attributes_with_values = attributes_with_values(false, false, attribute_names)
      self.class.connection.record = self
      result = self.class.connection.valid?(id, attributes_with_values)
      clear_ws_errors
      result
    rescue LogicalRecord::WsRecordInvalid
      add_ws_errors
      false
    end
    
    def add_ws_errors
      errors.clear if errors.present?
      ws_errors.each do |key, value|  
        if value.is_a?(Array)
          value.map { |msg| errors.add key, msg }
        else
          errors.add key, value
        end
      end if ws_errors.present?
    end
    
    def clear_ws_errors
      ws_errors.clear if ws_errors.present?
      errors.clear if errors.present? 
    end
  private

    # A hook to be overridden by association modules.
    def destroy_associations
    end

    def create_or_update
      raise ReadOnlyRecord if readonly?
      result = new_record? ? create : update
      result != false
    end

    # Updates the associated record with values matching those of the instance attributes.
    # Returns the number of affected rows.
    def update(attribute_names = @attributes.keys)
      attributes_with_values = attributes_with_values(false, false, attribute_names)
      return 0 if attributes_with_values.empty?
      klass = self.class
      
      begin
        klass.connection.record = self
        klass.connection.update(id, attributes_with_values)
      rescue LogicalRecord::WsRecordInvalid => exception
        raise exception
      end
    end

    # Creates a record with values matching those of the instance attributes
    # and returns its id.
    def create
      attributes_values = attributes_with_values(!id.nil?)

      new_id = self.class.unscoped.insert attributes_values, self

      self.id ||= new_id if self.class.primary_key

      IdentityMap.add(self) if IdentityMap.enabled?
      @new_record = false
      id
    end
  end
end
