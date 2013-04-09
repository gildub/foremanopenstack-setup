#!/usr/bin/env ruby
require 'json'
require 'logger' 
require 'rest-client'
require 'rubygems'

#TODO: Use foreman-api gem

@params_file_name = 'foreman-params.json'
@log_file         = STDOUT

def param?(key)
  @params.key?(key) && !@params[key].empty?
end

def get_env_id(env)
  envs = JSON.load(@client['environments'].get)
  env  = envs.detect { |e| e['environment'].key?('name') }
  env['environment']['id']
end

def get_class(name)
  res = @client['puppetclasses'].get(:params => { :search => name }) 
  JSON.load(res)
end 

def get_class_ids(classes) 
  ids = []
  classes.each do |puppetclasses|
    get_class(puppetclasses).each do |puppetclass|
      puppetclass[1].each do |details| 
        ids << details['puppetclass']['id']
      end
    end
  end
  ids
end

def create(cmd, data)
  response = @client[cmd].post(data)
rescue RestClient::UnprocessableEntity => e
  @log.warn("POST KO: #{data} => #{e.response}")
else
  @log.info("POST OK: #{data}")
end

def create_proxy(proxy)
  raise 'Incorrect or missing Proxy definitions' unless param?('proxy')
  proxy_url = 'https://' + proxy['host'] + ':8443'
  data = { :smart_proxy => { :name => proxy['name'], :url => proxy_url}}
  create('smart_proxies', data)
end

def create_globals(globals)
  raise 'Incorrect or missing Global Parameters definitions' unless param?('globals')
  globals.each do |name, value| 
    data = { :common_parameter => { :name => name, :value => value } }
    create('common_parameters', data)
  end
end

def create_hostgroups(hostgroups)  
  raise 'Incorrect or missing Hostgroups definitions' unless param?('hostgroups')
  hostgroups.each do |hostgroup| 
    env_id      = get_env_id(hostgroup[1]['environment'])
    classes_ids = get_class_ids(hostgroup[1]['puppetclasses'])

    create('hostgroups', :hostgroup => {
             :name => hostgroup[0],
             :environment_id => env_id,
             :puppetclass_ids => classes_ids
           }) 
  end
end

def usage
  puts "Usage: #{File.basename($0)} proxy | globals | hostgroups"
  puts " Multiple commands can be used at same time"
  exit
end

begin
# Init
  # Logs
  @log = Logger.new(@log_file)
  @log.datetime_format = "%d/%m/%Y %H:%M:%S" 
  $DEBUG ? @log.level = Logger::DEBUG : @log.level = Logger::INFO
   
  # JSON parameters
  raise "Missing file #{@params_file_name}" if !File.exist?(@params_file_name)
  params_file      = File.open(@params_file_name)
  @params          = JSON.load(params_file.read)

  # Session
  raise 'Incorrect or missing Host definitions' unless param?('host')
  @client = RestClient::Resource.new('https://' + @params['host']['name'] + '/api',
                                     :user => @params['host']['user'],
                                     :password => @params['host']['passwd'],
                                     :headers => { :accept => :json })
# Main
  usage unless ARGV[0]
  while ARGV[0]
    case ARGV[0]
    when 'proxy' 
      create_proxy(@params['proxy'])
    when 'globals' 
      create_globals(@params['globals'])
    when 'hostgroups'
      create_hostgroups(@params['hostgroups'])
    else
      usage
    end
    ARGV.shift
  end
rescue RuntimeError => e
  @log.fatal(e)
  exit
end

