#
# Tangerine Tree
# This program generates APKs and a download link for a group.
#
# It works by using the AndroidCouchbaseCallback generated APK as a shell.
# Then we replace the database from another source. We peel the Tangerine
# and insert any kind of fruit we want.
#
# Note: the database that is being replicated should contain a couchapp.
#

require 'rubygems'
require 'sinatra'
require 'sinatra/cross_origin'
require 'rest-client'
require 'json'
require 'logger'
require './config.rb'

#
#
#

set :allow_origin, :any
set :allow_methods, [:get, :post, :options]
set :allow_credentials, true
set :max_age, "1728000"
set :protection, :except => :json_csrf

$character_set = "abcdeghikmnoprstuwxyz".split("") # optimized for mobiles and human error
$logger = Logger.new "tree.log"


get "/" do
  "
  <img src='http://farm1.staticflickr.com/134/352637689_a21b5bb3e1_o.jpg'>
  <br>
  <small>Photo by <a href='http://www.flickr.com/photos/mabar/352637689/'>Mabar</a></small>
  "

end

#
# handle a request to make an APK
#

post "/make/:group" do

  cross_origin

  content_type :json

  auth_errors = []
  auth_errors << "a username" if params[:user] == nil
  auth_errors << "a password" if params[:pass] == nil
  auth_errors << "a group"    if params[:group].length == 0

  #halt 403, { :error => "Please provide #{andify(auth_errors)}."} if auth_errors.length > 0

  copied_group = "#{$servers[:local]}/copied-group-#{params[:group]}"
  source_group = "#{$servers[:main]}/group-#{params[:group]}"


  #
  # Authenticate user for the group
  #
  auth_response = RestClient.post $servers[:robbert], { 
    :action => "am_admin", 
    :group  => params[:group], 
    :user   => params[:user]
  }
  halt_error(403, "Sorry, you have to be an admin within the group to make an APK.", "Not an admin. #{params.to_json}") if JSON.parse(auth_response.body)["message"] == "no"

  #
  # Make APK, place it in token-directory for download
  #

  token = get_token()

  # Remove current database, if it exists.
  begin
    RestClient.delete copied_group
  rescue RestClient::ResourceNotFound
    # do nothing if it 404s
  end

  # get a list of _ids for the assessments not archived
  assessments_view = JSON.parse(RestClient.post("#{source_group}/_design/ojai/_view/assessmentsNotArchived", {}.to_json, :content_type => :json, :accept => :json))
  list_query_data = assessments_view['rows'].map { |row| row['id'][-5..-1] }
  list_query_data = {"keys" => list_query_data}

  # get a list of files associated with those assessments  
  id_view = JSON.parse(RestClient.post("#{source_group}/_design/ojai/_view/byDKey",list_query_data.to_json, :content_type => :json,:accept => :json ))

  id_list = id_view['rows'].map { |row| row['id'] }

  id_list << "settings"
  id_list << "templates"
  id_list << "configuration"
  id_list << "_design/ojai"

  # replicate group to new local here
  replicate_response = RestClient.post("#{$servers[:main]}/_replicate", {
    :source  => "#{source_group}", 
    :target  => "#{copied_group}", # "copied-" because debugging on same server 
    :doc_ids => id_list,
    :create_target => true
  }.to_json, :content_type => :json )

  halt_error 500, "Failed to replicate temporary database.", "Failed to replicate #{params[:group]}." if replicate_response.code != 200

  # change the settings
  settings = JSON.parse(RestClient.get("#{copied_group}/settings"))
  # the absence of this setting causes tangerine to check
  settings.delete('adminEnsured')
  settings['context'] = "mobile"
  settings['log'] = []

  warn "going to save"
  warn settings.to_json


  mobilfy_response = RestClient.put("#{copied_group}/settings", settings.to_json, :content_type => :json, :accept => :json)

  warn mobilfy_response
  warn mobilfy_response.code
  halt_error(500, "Failed to prepare mobile database.", "Could not save settings for #{params[:group]}") if !(mobilfy_response.code >= 200 && mobilfy_response.code < 300)


  #
  # for the ojai-parallel, replicate into proper design doc
  #

  # See if one exists aready
  get_request = Net::HTTP::Get.new("/copied-group-#{params[:group]}/_design/tangerine")
  get_response = $main_http.request get_request
  if get_response.code.to_i == 200
    copy_rev = "?rev=" + JSON.parse(get_response.body).to_hash["_rev"]
  else
    copy_rev = ""
  end

  # copy _design/ojai to _design/tangerine
  copy_request = Net::HTTP::Copy.new("/copied-group-#{params[:group]}/_design/ojai")
  copy_request["Destination"] = "_design/tangerine" + copy_rev
  copy_request.basic_auth $username, $password
  copy_response = $main_http.request copy_request

  copy_code = copy_response.code.to_i
  halt_error 500, "Tree's couch failed to rename design doc.", "Could not copy for #{params[:group]}." if !(copy_code >= 200 && copy_code < 300)

  # @TODO
  # Add admin users from group to APK
  # download _security doc from group
  # get list of admins
  # look up each admin's _user doc
  # open Android-Couchbase-Callback's local.ini file
  # remove all the admins there except localadmin
  # save all admin users from the group like this:
  #  #{name} = -hashed-#{passwordSHA},#{passwordSalt}

  warn "trying to ensure commit with the following"
  warn File.join(copied_group, "_ensure_full_commit")
  RestClient.post(File.join(copied_group, "_ensure_full_commit"), "", :content_type => 'application/json')

  begin

    # standardize all groups DBs here as tangerine.couch
    db_file     = "copied-group-#{params[:group]}.couch"
    group_db    = File.join( $couch_db_path, db_file )
    target_dir  = File.join( Dir.pwd, "Android-Couchbase-Callback", "assets" )

    target_path = File.join( target_dir, "tangerine.couch" )
    # bring in the dog
    `rm #{target_path}`
    # put out the cat
    `ln -s #{group_db} #{target_path}`

  rescue Exception => e
    halt_error 500, "Failed to copy database.", "Could not copy #{params[:group]}'s database into assets. #{e}"
  end

  
  # zip APK and place it in token download directory
  begin

    current_dir = Dir.pwd
    ensure_dir current_dir, "apks", token

    groupstamp_location = File.join( current_dir, "apks", token, params[:group] )
    `touch #{groupstamp_location}`

    acc_dir = File.join Dir.pwd, "Android-Couchbase-Callback"
    assets_dir = File.join Dir.pwd, "Android-Couchbase-Callback", "assets"

    apk_path = File.join( current_dir, "apks", token, "tangerine.apk" )

    warn "tried to put in"
    warn apk_path

    Dir.chdir(acc_dir) {
      `ant clean`
      `ant debug`
      `mv bin/Tangerine-debug.apk #{apk_path}`
    }

  rescue Exception => e
    halt_error 500, "Failed to prepare APK.", "Could not copy #{params[:group]}'s database into assets. #{e}"
  end
  
  return { :token => token }.to_json

end # post "/make/:group" do


get "/apk/:token" do

  cross_origin

  current_dir = Dir.pwd

  apk_name = "tangerine.apk"
  apk_path = File.join( current_dir, 'apks', params[:token], apk_name)

  if File.exist? apk_path
    send_file( apk_path ,
      :disposition => 'attachment', 
      :filename    => File.basename(apk_name)
    )
  else
    content_type :json

    halt_error 404, "No APK found, invalid token.", "(404) #{params[:token]}."
  end

end # of get "/apk/:token" do

#
# Helper functions
#

def ensure_dir( *dirs )
  path = ""
  for current in dirs
    path = File.join path, current
    Dir::mkdir path if not File.directory? path
  end
rescue Exception => e
  $logger.error "Couldn't make directory. #{e}"
end

def get_token()
  (1..6).map{|x| $character_set[rand($character_set.length)]}.join()
end

def mkdir(dir)
  name = File.join Dir::pwd, dir
  return nil if File.directory? name
  Dir::mkdir(name)
rescue Exception => e
  $logger.error "Couldn't make directory. #{e}"
end

def halt_error(code, message, log_message)
  $logger.error log_message
  halt code, { :error => message }.to_json
end

def andify( nouns )
  #last = nouns.pop()
  return nouns#nouns.join(", ") + ", and " + last
end

def orify( nouns )
  #last = nouns.pop()
  return nouns#nouns.join(", ") + ", or " + last
end
