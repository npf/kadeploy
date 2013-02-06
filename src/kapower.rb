#!/usr/bin/ruby -w

# Kadeploy 3.1
# Copyright (c) by INRIA, Emmanuel Jeanvoine - 2008-2011
# CECILL License V2 - http://www.cecill.info
# For details on use and redistribution please refer to License.txt

#Kadeploy libs
require 'config'
require 'port_scanner'

#Ruby libs
require 'drb'
require 'timeout'

class KapowerClient
  @site = nil
  @files_ok_nodes = nil
  @files_ko_nodes = nil
  
  def initialize(site, files_ok_nodes, files_ko_nodes)
    @site = site
    @files_ok_nodes = files_ok_nodes
    @files_ko_nodes = files_ko_nodes
  end

  # Print a message (RPC)
  #
  # Arguments
  # * msg: string to print
  # Output
  # * prints a message
  def print(msg)
    if (@site == nil) then
      puts msg
    else
      puts "(#{@site}) #{msg}"
    end
  end

  # Print the results of the deployment (RPC)
  #
  # Arguments
  # * nodes_ok: instance of NodeSet that contains the nodes correctly deployed
  # * nodes_ko: instance of NodeSet that contains the nodes not correctly deployed
  # Output
  # * nothing    
  def generate_files(nodes_ok, nodes_ko)
    t = nodes_ok.make_array_of_hostname
    if (not t.empty?) then
      file_ok = Tempfile.new("kapower_nodes_ok")
      @files_ok_nodes.push(file_ok)     
      t.each { |n|
        file_ok.write("#{n}\n")
      }
      file_ok.close
    end

    t = nodes_ko.make_array_of_hostname
    if (not t.empty?) then
      file_ko = Tempfile.new("kapower_nodes_ko")
      @files_ko_nodes.push(file_ko)      
      t.each { |n|
        file_ko.write("#{n}\n")
      }
      file_ko.close
    end
  end

  # Test method to check that the client is still there (RPC)
  #
  # Arguments
  # * nothing
  # Output
  # * nothing
  def test
  end
end

# Disable reverse lookup to prevent lag in case of DNS failure
Socket.do_not_reverse_lookup = true

exec_specific_config = ConfigInformation::Config.load_kapower_exec_specific()

if exec_specific_config != nil then
  nodes_by_server = Hash.new
  remaining_nodes = exec_specific_config.node_array.clone

  if (exec_specific_config.multi_server) then
    exec_specific_config.servers.each_pair { |server,info|
      if (server != "default") then
        if (PortScanner::is_open?(info[0], info[1])) then
          distant = DRb.start_service()
          uri = "druby://#{info[0]}:#{info[1]}"
          kadeploy_server = DRbObject.new(nil, uri)
          begin
            Timeout.timeout(8) {
              nodes_known,remaining_nodes = kadeploy_server.check_known_nodes(remaining_nodes)
              if (nodes_known.length > 0) then
                nodes_by_server[server] = nodes_known
              end
            }
          rescue Timeout::Error
            puts "Cannot check the nodes on the #{server} server"
          end
          distant.stop_service()
          break if (remaining_nodes.length == 0)
        else
          puts "The #{server} server is unreachable"
        end
      end
    }
    if (not remaining_nodes.empty?) then
      puts "The nodes #{remaining_nodes.join(", ")} does not belongs to any server"
      exit(2)
    end
  else
    if (PortScanner::is_open?(exec_specific_config.servers[exec_specific_config.chosen_server][0], exec_specific_config.servers[exec_specific_config.chosen_server][1])) then
      nodes_by_server[exec_specific_config.chosen_server] = exec_specific_config.node_array
    else
      puts "The #{exec_specific_config.chosen_server} server is unreachable"
      exit(2)
    end
  end

  tid_array = Array.new
  Signal.trap("INT") do
    puts "SIGINT trapped, let's clean everything ..."
    exit(1)
  end
  files_ok_nodes = Array.new
  files_ko_nodes = Array.new
  nodes_by_server.each_key { |server|
    tid_array << Thread.new {

      #Connect to the server
      distant = DRb.start_service()
      
      uri = "druby://#{exec_specific_config.servers[server][0]}:#{exec_specific_config.servers[server][1]}"
      kadeploy_server = DRbObject.new(nil, uri)

      if exec_specific_config.get_version then
        puts "(#{server}) Kapower version: #{kadeploy_server.get_version()}"
      else
        if (exec_specific_config.multi_server) then
          kapower_client = KapowerClient.new(server, files_ok_nodes, files_ko_nodes)
        else
          kapower_client = KapowerClient.new(nil, files_ok_nodes, files_ko_nodes)
        end
        local = DRb.start_service(nil, kapower_client)
        if /druby:\/\/([a-zA-Z]+[-\w.]*):(\d+)/ =~ local.uri
          content = Regexp.last_match
          hostname = Socket.gethostname
          client_host = String.new
          if hostname.include?(client_host) then
            #It' best to get the FQDN
            client_host = hostname
          else
            client_host = content[1]
          end
          client_port = content[2]
          cloned_config = exec_specific_config.clone
          cloned_config.node_array = nodes_by_server[server]
          kadeploy_server.run("kapower_sync", exec_specific_config, client_host, client_port)
        else
          puts "The URI #{local.uri} is not correct"
        end
        local.stop_service()
      end
      distant.stop_service()
    }
  }
  tid_array.each { |tid|
    tid.join
  }


  #We merge the files
  if (exec_specific_config.nodes_ok_file != "") then
    File.delete(exec_specific_config.nodes_ok_file) if File.exist?(exec_specific_config.nodes_ok_file)
    if (not files_ok_nodes.empty?) then
      files_ok_nodes.each { |file|
        system("cat #{file.path} >> #{exec_specific_config.nodes_ok_file}")
      }
    end
  end
  if (exec_specific_config.nodes_ko_file != "") then
    File.delete(exec_specific_config.nodes_ko_file) if File.exist?(exec_specific_config.nodes_ko_file)
    if (not files_ko_nodes.empty?) then
      files_ko_nodes.each { |file|
        system("cat #{file.path} >> #{exec_specific_config.nodes_ko_file}")
      }
    end
  end

  exit(0)
else
  exit(1)
end
