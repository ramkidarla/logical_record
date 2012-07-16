LogicalRecord
==============

LogicalRecord allows to use a Restfull Json web services as models.


Usage:

class User < LogicalRecord::Base

	establish_connection :adapter => 'restfull_json', 
              :host => '192.168.11.8',
              :use_ssl => false,
              :hydra => HYDRA,
              :use_api_key => true,
              :api_key_name => 'access_token',
              :api_key => "2MNFP7SrgD3QhuvuUY0hD2P8s7MSdCewHySAYvQo",
              :resource_path => "/api/v1/users"

end

Supports:

1) CRUD Methods

    - insert
    - create, create!
    - save, save!
    - Update #=> update_attribute, update_attributes, update_attributes!, update_column, update_all
    - delete, delete!, delete_all
    - destroy, destroy_all

2) Finder Methods

	- User.find(id)
	- User.find(ids_array)
	- User.find(:first)/ User.first
	- User.where(:address_id => '1076').all
 	- users = User.where(:address_id => '4')
	- fiusers = users.order('email DESC').limit(3)
         
3) Dynamic finders

	- User.find_by_email('mazie.goyette3@kulaslangosh.net')

4) Associations/Relation Ships
        
	- u = User.find(id)
	- u.address
	- users = User.all(:joins => :password_histories)
	

5) Scopes, Default Scope

	- User.active.by_role('Admin')

6) Call Backs

	- before_save
	- before_destroy
	- after_save
        
7) Validations 
        
	-  valid?         # Server side validations
	-  valid_local?   # Only local validations
        
========================
Modifications 
========================

We took latest ActiveRecord and modified accordingily to work via restfull web services

Below the major changes

	- Removed all database adapters
	- Added a new connection_adapters/resetfull_json_adapters.rb
	- Done some modifications in below files
           	
		1) connection_adapters/abstract/database_statement.rb
		2) connection_adapters/abstract_adapter.rb
		3) attribute_methods.rb
		4) errors.rb
		5) persistence.rb
		6) relation.rb
		7) sanitization.rb
		8) validations.rb


==========================
Issues
==========================
	- Suppose user model inherits LogicalRecord and associated model password history model inherits ActiveRecord,
	  While deleting user object, associated password_histories will be deleted, if connection lost then user object will remain same
