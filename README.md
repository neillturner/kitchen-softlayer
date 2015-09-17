[![Gem Version](https://badge.fury.io/rb/kitchen-softlayer.svg)](http://badge.fury.io/rb/kitchen-softlayer)
[![Gem Downloads](http://ruby-gem-downloads-badge.herokuapp.com/kitchen-softlayer?type=total&color=brightgreen)](https://rubygems.org/gems/kitchen-softlayer)
[![Build Status](https://travis-ci.org/neillturner/kitchen-softlayer.png)](https://travis-ci.org/neillturner/kitchen-softlayer)

# Kitchen::Softlayer

A Test Kitchen Driver for Softlayer


## Installation

Add this line to your application's Gemfile:

    gem 'kitchen-softlayer'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kitchen-softlayer

## Usage

By default set the following environment variables to your softlayer credentials:

```
      softlayer_username
      softlayer_api_key
      softlayer_default_datacenter    (optional)
      softlayer_default_domain        (optional)
```

So you don't need to code these in the .kitchen.yml file which is much better from a security point
of view as the kitchen.yml file can be checked in to source control without containing key data.


An example of the driver options in your `.kitchen.yml` file:

```yaml
    driver:
      name: softlayer
        key_name: 'myuploadedsshkeylabel'
        ssh_key: C:/mykeys/my_private_sshkey.pem
        username: root
        server_name: 'myserver-test'
        hostname: 'MyProject-test01'
        flavor_id: m1.tiny
     #  image_id: '3b235124-a190-40b5-9720-c020e61b99e1'
        os_code: 'CENTOS_7_64'
        domain: softlayer.com
        private_network_only: true
        cpu: 1,
        ram: 1024,
        datacenter: lon02
```

### os_code and image_id
you need to either specify softlayer's operating System Reference Code via parameter os_code
or an image_id.

### private_network_only
By default this parameter is set to false so no public network with be created.
For test-kitchen to access the server via ssh it needs to be on the softlayer private VPN. See:

[Using SSL VPN](http://knowledgelayer.softlayer.com/procedure/using-ssl-vpn)

### ssh_key
 Currently the driver only supports using SSH keys to access servers. This requires that you upload an SSH Key in Softlayer see:

[SSH Keys](http://knowledgelayer.softlayer.com/procedure/ssh-keys-0)

 in the kitchen.yml file specify the label of the ssh key as the parameter key_name
 and specify the private key for the uploaded public key as parameter ssh_key.

The `image_ref` and `flavor_ref` options can be specified as an exact id,
an exact name, or as a regular expression matching the name of the image or flavor.

### hostname

the driver checks for a server with the hostname and will use that server instead of creating another one.

### disable_ssl_validation

the driver uses the fog-softlayer ruby client to communicate with softlayer.
If you get SSL certificate validation errors then the workaround is to set disable SSL cert validation to true
however it is better to set the environment variable 'SSL_CERT_FILE' to a valid certificate file.

# Softlayer Driver Options

key | default value | Notes
----|---------------|--------
softlayer_username | ENV['softlayer_username']
softlayer_api_key | ENV['softlayer_api_key']
softlayer_default_datacenter | ENV['softlayer_default_datacenter']
softlayer_default_domain | ENV['softlayer_default_domain']
server_name | nil | Server Name
key_name | nil | the label of the uploaded key
ssh_key| nil | file location of private key
disable_ssl_validation | false | ssl validation for fg softlayer api
username | 'root' | server's administration user
password | nil | server's administration password
port | '22' | ssh port of servef
hostname| nil | hostname of server
domain | ENV['softlayer_default_domain'] | domain nane of server
fqdn | nil | fully qualified domain name
cpu | nil | no of cpus
ram | nil | memory size
disk | nil | disk size
flavor_id | nil | type of server i.e. m1.tiny
bare_metal | false | server to be created on bare metal (takes longer)
os_code | nil | softlayer's operating System Reference Code
image_id | nil | image id for server
ephemeral_storage | nil | storage
network_components | nil | network
ssh_timeout | 300 | timeout to ssh when server starting
account_id | nil | softlayer account id
datacenter | ENV['softlayer_default_datacenter'] | datacenter code
single_tenant | false | don't share server
global_identifier | nil | softlayer global id
hourly_billing_flag | true
tags | [] | tags for the server
private_network_only | false | if only a private network
use_private_ip_with_public_network | false | otherwise uses public ip
user_data | nil | user data for server
uid | nil | softlayer global id
vlan | nil | numeric id of private_vlan for server
private_vlan | nil | numeric id of private_vlan for server
provision_script | nil | url of provision script to run

NOTE: provision_script parameter needs pull request [#73](https://github.com/fog/fog-softlayer/pull/73)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Run style checks and RSpec tests (`bundle exec rake`)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create new Pull Request
