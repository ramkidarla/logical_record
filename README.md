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