#!/usr/bin/env ruby
#TODO: Use foreman-api gem
require 'rubygems'
require 'json'
require 'logger' 
require 'rest-client'

# Default
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
  data = { :smart_proxy => { :name => proxy['name'], :url => proxy['host'] } }
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

# TODO: replace with ssh commands for remote install
def import_modules(modules)
  # Clone Git repos
  raise 'Incorrect or missing Puppet Modules definitions' unless modules
  modules.each do |mod|
    options = mod['options'] if mod.has_key?('options') && !mod['options'].empty? 
    command="git clone #{options} #{mod['source']} #{mod['target']}"
    system(command)
    raise "Error with git clone #{command}" if $?.exitstatus != 0
    @log.info("Git Clone Ok: #{mod['source']}")
  end

  # Import puppet modules into Foreman 
  command="cd /usr/share/foreman && rake puppet:import:puppet_classes[batch] RAILS_ENV=production"
  system(command)
  @log.info('Import puppet classes ok')
end

def usage
  puts "Usage: #{File.basename($0)} all | proxy | modules | globals | hostgroups"
  exit
end

def init
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
end

def all(params)
  # Order matters!
  create_proxy(params['proxy'])
  import_modules(params['modules'])
  create_globals(params['globals'])
  create_hostgroups(params['hostgroups'])
end

begin
  # Options
  usage unless ARGV[0]
  until ARGV[0] !~ /^-./
    case ARGV[0]
    when '-c' 
      ARGV.shift
      @params_file_name = ARGV[0]
    when '-l'
      ARGV.shift
      @log_file         = ARGV[0]
    end
    ARGV.shift
  end
  init

  # Command
  usage unless ARGV[0]
  until ARGV.empty?
    case ARGV[0]
    when 'proxy' 
      create_proxy(@params['proxy'])
    when 'modules'
      import_modules(@params['classes'])
    when 'globals' 
      create_globals(@params['globals'])
    when 'hostgroups'
      create_hostgroups(@params['hostgroups'])
    when 'all'
      all(@params)
    else
      usage
    end
    ARGV.shift
  end
rescue RuntimeError => e
  @log.fatal(e)
  exit
end

