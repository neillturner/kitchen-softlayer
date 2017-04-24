# Encoding: utf-8

#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fog'
require 'kitchen'
require 'socket'
require 'fog/softlayer'

module Kitchen
  module Driver
    # Softlayer driver for Kitchen.
    # rubocop:disable Metrics/LineLength
    class Softlayer < Kitchen::Driver::SSHBase
      default_config :server_name, nil
      default_config :server_name_prefix, nil
      default_config :key_name, nil
      required_config :key_name
      default_config :ssh_key do
        %w[id_rsa id_dsa].map do |k|
          f = File.expand_path("~/.ssh/#{k}")
          f if File.exist?(f)
        end.compact.first
      end

      required_config :ssh_key
      default_config :disable_ssl_validation, false
      default_config :username, 'root'
      default_config :password, nil
      default_config :port, '22'
      default_config :domain, ENV['softlayer_default_domain']
      default_config :fqdn, nil
      default_config :cpu, nil
      default_config :ram, nil
      default_config :disk, nil
      default_config :flavor_id, nil
      default_config :bare_metal, false
      default_config :os_code, nil
      default_config :image_id, nil
      default_config :ephemeral_storage, nil
      # keypair found from keyname
      # default_config :key_pairs, nil
      default_config :network_components, nil
      default_config :softlayer_username, ENV['softlayer_username']
      default_config :softlayer_api_key, ENV['softlayer_api_key']
      default_config :softlayer_default_datacenter, ENV['softlayer_default_datacenter']
      default_config :softlayer_default_domain, ENV['softlayer_default_domain']
      default_config :ssh_timeout, 300
      default_config :destroy_wait, true
      default_config :destroy_timeout, 300
      default_config :account_id, nil
      default_config :datacenter, ENV['softlayer_default_datacenter']
      default_config :single_tenant, false
      default_config :global_identifier, nil
      default_config :hourly_billing_flag, true
      default_config :tags, nil
      default_config :private_network_only, false
      default_config :use_private_ip_with_public_network, false
      default_config :user_data, nil
      default_config :uid, nil
      default_config :tags, []
      default_config :vlan, nil
      default_config :private_vlan, nil
      default_config :provision_script, nil
      default_config :ssh_via_hostname, false
      default_config :alternate_ip, nil
      default_config :connect_timeout, 120
      default_config :read_timeout, 120
      default_config :write_timeout, 120

      # rubocop:disable Metrics/AbcSize
      def create(state)
        config_server_name
        config[:disable_ssl_validation] && disable_ssl_validation
        config[:fqdn] = "#{config[:server_name]}.#{config[:domain]}"
        debug "fqdn: #{config[:fqdn]}"
        debug "server_name: #{config[:server_name]}"
        debug "server_name_prefix: #{config[:server_name_prefix]}"
        server = create_server unless find_server(config[:fqdn])
        state[:server_id] = server.id
        info "Softlayer instance <#{state[:server_id]}> created."
        server.wait_for do
          print '.'
          ready?
        end
        info "\n(server ready)"
        tag_server(server)
        # set state[:hostname] to be able to setup ssh using Fog::SSH
        state[:hostname] = if config[:ssh_via_hostname]
                             config[:server_name]
                           elsif config[:alternate_ip]
                             config[:alternate_ip]
                           else
                             get_ip(server)
                           end
        setup_ssh(server, state)
        wait_for_ssh_key_access(state)
      rescue Fog::Errors::Error, Excon::Errors::Error => ex
        raise ActionFailed, ex.message
      end

      def destroy(state)
        return if state[:server_id].nil?

        config[:disable_ssl_validation] && disable_ssl_validation
        server = compute.servers.get(state[:server_id])
        server.destroy unless server.nil? || server.id.nil?
        wait_for_server_to_delete(state) if config[:destroy_wait]
        info "Softlayer instance <#{state[:server_id]}> destroyed."
        state.delete(:server_id)
        state.delete(:server_name)
      end

      private

      # Set the proper server name in the config
      def config_server_name
        return if config[:server_name]

        config[:server_name] = if config[:server_name_prefix]
                                 server_name_prefix(config[:server_name_prefix])
                               else
                                 default_name
                               end
      end

      def wait_for_server_to_delete(state)
        ((config[:destroy_timeout].to_i / 15).floor).times do
          info 'Deleting server in softlayer'
          sleep 15
          server = compute.servers.get(state[:server_id])
          return if server.nil? || server.id.nil?
        end
        raise "#{config[:destroy_timeout]} seconds went by and server not deleted by softlayer"
      end

      def wait_for_ssh_key_access(state)
        new_state = build_ssh_args(state)
        new_state[2][:number_of_password_prompts] = 0
        info 'Checking ssh key authentication'

        (config[:ssh_timeout].to_i).times do
          ssh = Fog::SSH.new(*new_state)
          begin
            ssh.run([%(uname -a)])
          rescue => e
            info "Server not yet accepting SSH key: #{e.message}"
            sleep 1
          else
            info 'SSH key authetication successful'
            return
          end
        end
        raise "#{config[:ssh_timeout]} seconds went by and we couldn't connect, somethings broken"
      end

      def compute
        @compute_connection ||= Fog::Compute.new(
          provider: :softlayer,
          softlayer_username: config[:softlayer_username],
          softlayer_api_key: config[:softlayer_api_key],
          softlayer_default_datacenter: config[:softlayer_datacenter],
          softlayer_default_domain: config[:softlayer_domain]
        )
      end

      def network
        @network_connection ||= Fog::Network.new(
          provider: :softlayer,
          softlayer_username: config[:softlayer_username],
          softlayer_api_key: config[:softlayer_api_key]
        )
      end

      def find_server(fqdn)
        s = nil
        srvs = compute.servers.all.select { |x| x.fqdn == fqdn }
        unless srvs.empty?
          s = srvs[0]
          info "Server with fqdn #{fqdn} already created"
        end
        s
      end

      def find_image(image_name)
        id = nil
        images = compute.images.all
        images.each do |image|
          if image.name == image_name
            id = image.id
            debug "Found public image #{id} for name #{image_name}"
          end
        end
        images = compute.images.private
        images.each do |image|
          if image.name == image_name
            id = image.id
            debug "Found private image #{id} for name #{image_name}"
          end
        end
        raise "No image found with name #{image_name}" if id.nil?
        id
      end

      def find_network(vlan)
        debug "Looking for network for vlan number #{vlan}"
        response = network.list_networks
        response.body.each do |r|
          next unless r['vlanNumber'] == vlan
          debug "Found network id #{r['id']} for vlan number #{r['vlanNumber']}"
          return r['id']
        end
        raise "No network found for vlan number #{r['vlanNumber']}"
      end

      def create_server
        server_def = init_configuration
        #   TODO: figure out network options
        #    if config[:network_ref]
        #      networks = [].concat([config[:network_ref]])
        #      server_def[:nics] = networks.flatten.map do |net|
        #        { 'net_id' => find_network(net).id }
        #      end
        #    end
        %i[
          username
          password
          port
          domain
          fqdn
          cpu
          ram
          disk
          flavor_id
          bare_metal
          os_code
          image_id
          ephemeral_storage
          network_components
          account_id
          single_tenant
          global_identifier
          tags
          user_data
          uid
          vlan
          private_vlan
          provision_script
        ].each do |c|
          server_def[c] = optional_config(c) if config[c]
        end
        debug "server_def: #{server_def}"
        compute.servers.create(server_def)
      end

      def init_configuration
        {
          name: config[:server_name],
          key_pairs: [compute.key_pairs.by_label(config[:key_name])],
          datacenter: config[:datacenter],
          hourly_billing_flag: config[:hourly_billing_flag],
          private_network_only: config[:private_network_only]
        }
      end

      def optional_config(c)
        case c
        when :vlan
          find_network(config[c])
        when :private_vlan
          find_network(config[c])
        when :image_id
          return config[c] if config[c].match('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
          find_image(config[c])
        else
          config[c]
        end
      end

      # Generate what should be a unique server name up to 63 total chars
      # Base name:    15
      # Username:     15
      # Hostname:     23
      # Random string: 7
      # Separators:    3
      # ================
      # Total:        63
      def default_name
        [
          instance.name.gsub(/\W/, '')[0..14],
          (Etc.getlogin || 'nologin').gsub(/\W/, '')[0..14],
          Socket.gethostname.gsub(/\W/, '')[0..22],
          Array.new(7) { rand(36).to_s(36) }.join
        ].join('-')
      end

      def server_name_prefix(server_name_prefix)
        # Generate what should be a unique server name with given prefix
        # of up to 63 total chars
        #
        # Provided prefix:  variable, max 54
        # Separator:        1
        # Random string:    8
        # ===================
        # Max:              63
        #
        if server_name_prefix.length > 54
          warn 'Server name prefix too long, truncated to 54 characters'
          server_name_prefix = server_name_prefix[0..53]
        end

        server_name_prefix.gsub!(/\W/, '')

        if server_name_prefix.empty?
          warn 'Server name prefix empty or invalid; using fully generated name'
          default_name
        else
          random_suffix = ('a'..'z').to_a.sample(8).join
          server_name_prefix + '-' + random_suffix
        end
      end

      # TODO: code has support for multiple ips but not used.

      def get_public_private_ips(server)
        pub = server.public_ip
        priv = server.private_ip
        [pub, priv]
      end

      def get_ip(server)
        pub, priv = get_public_private_ips(server)
        pub, priv = parse_ips(pub, priv)
        pub[config[:public_ip_order].to_i] ||
          priv[config[:private_ip_order].to_i] ||
          raise(ActionFailed, 'Could not find an IP')
        return priv[0] if config[:use_private_ip_with_public_network] && !config[:private_network_only]
        return priv[0] if config[:private_network_only]
        pub[0]
      end

      def parse_ips(pub, priv)
        pub = Array(pub)
        priv = Array(priv)
        if config[:use_ipv6]
          [pub, priv].each { |n| n.select! { |i| IPAddr.new(i).ipv6? } }
        else
          [pub, priv].each { |n| n.select! { |i| IPAddr.new(i).ipv4? } }
        end
        [pub, priv]
      end

      def setup_ssh(server, state)
        tcp_check(state)
        info "Using Softlayer keypair <#{config[:key_name]}>"
        info "Using private SSH key <#{config[:ssh_key]}>"
        state[:ssh_key] = config[:ssh_key]
        # we don't call this as key_name must be set.
        do_ssh_setup(state, config, server) unless config[:key_name]
      end

      def tcp_check(state)
        # allow driver config to bypass SSH tcp check -- because
        # it doesn't respect ssh_config values that might be required
        if config[:no_ssh_tcp_check]
          sleep(config[:no_ssh_tcp_check_sleep])
        else
          debug("wait_for_sshd hostname: #{state[:hostname]},username: #{config[:username]},port: #{config[:port]}")
          wait_for_sshd(state[:hostname],
                        config[:username],
                        port: config[:port])
        end
        info '(ssh ready)'
      end

      def disable_ssl_validation
        require 'excon'
        Excon.defaults[:ssl_verify_peer] = false
      end

      def tag_server(server)
        server.add_tags(config[:tags])
      end

      #   TODO: add these checks
      #    def find_image(image_ref)
      #      image = find_matching(compute.images, image_ref)
      #      fail(ActionFailed, 'Image not found') unless image
      #      debug "Selected image: #{image.id} #{image.name}"
      #      image
      #    end

      #    def find_flavor(flavor_ref)
      #      flavor = find_matching(compute.flavors, flavor_ref)
      #      fail(ActionFailed, 'Flavor not found') unless flavor
      #      debug "Selected flavor: #{flavor.id} #{flavor.name}"
      #      flavor
      #    end

      #    def find_network(network_ref)
      #      net = find_matching(network.networks.all, network_ref)
      #      fail(ActionFailed, 'Network not found') unless net
      #      debug "Selected net: #{net.id} #{net.name}"
      #      net
      #    end

      #    def find_matching(collection, name)
      #      name = name.to_s
      #      if name.start_with?('/') && name.end_with?('/')
      #        regex = Regexp.new(name[1...-1])
      #      # check for regex name match
      #        collection.each { |single| return single if regex =~ single.name }
      #      else
      #      # check for exact id match
      #        collection.each { |single| return single if single.id == name }
      #      # check for exact name match
      #        collection.each { |single| return single if single.name == name }
      #      end
      #      nil
      #    end
    end
  end
end
