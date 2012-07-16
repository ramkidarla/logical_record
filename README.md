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

It Supports

1) CRUD Methods

    - Create #=> create, create!
         - u = User.find(1080)
         - user_attributes = u.attributes
         - u1 = User.create(user_attributes)
         - u1.email += "com"
         - u1.password = "pnws@123"
         - u1.password_confirmation = "pnws@123"
         - u1.save

    - Update #=> update_attribute, update_attributes, update_attributes!
    - Save
    - Delete
    - Destroy

2) Finder Methods

	- u = User.find(1080)
	- u = User.find(1080, 1077)
	- u = User.find(:first)/ User.first
	- users = User.where(:address_id => '1076').all
	
	- users = User.where(:address_id => '4')
	- fiusers = users.order('email DESC').limit(3)

3) Dynamic finders

	- u = User.find_by_email('mazie.goyette3@kulaslangosh.net')

4) Associations/Relation Ships

	- u.address
	- users = User.all(:joins => :password_histories)
	- users.each do |u|
	- puts u.id
	- puts u.password_histories.count
	- end  

5) Scopes, Default Scope

	- User.active.by_role('Admin')

6) Call Backs

	- before_save
	- before_destroy
	       - u.destroy
	- after_save

7) Validations 

========================
Modifications 
========================

We took latest ActiveRecord and modified accordingily to work via restfull web services

Below the major changes

	- Removed all database adapters
	- Added a new restfull adapter
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
