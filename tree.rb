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
require 'net/http'
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
$l = Logger.new "tree.log"

#
# handle a request to make an APK
#

post "/:group" do

  cross_origin

  content_type :json

  auth_errors = []
  auth_errors << "a username" if params[:user] == nil
  auth_errors << "a password" if params[:pass] == nil
  auth_errors << "a group"    if params[:group].length == 0

  $l.info "New #{params[:group]} by #{params[:user]}"

  #halt 403, { :error => "Please provide #{andify(auth_errors)}."} if auth_errors.length > 0

  copied_group = "#{$servers[:local]}/db/copied-group-#{params[:group]}"
  source_group = "#{$servers[:main]}/db/group-#{params[:group]}"


  #
  # Authenticate user for the group
  #
  auth_response = RestClient.post $servers[:robbert], { 
    :action => "am_admin", 
    :group  => params[:group], 
    :user   => params[:user]
  }
  $l.debug "Robbert: #{auth_response.to_json}"
  halt_error(403, "Sorry, you have to be an admin within the group to make an APK.", "Not an admin. #{params.to_json}") if JSON.parse(auth_response.body)["message"] == "no"

  #
  # Make APK, place it in token-directory for download
  #

  token = get_token()
  $l.debug "Token: #{token}"

  # Remove current database, if it exists.
  begin
    RestClient.delete copied_group
  rescue RestClient::ResourceNotFound
    # do nothing if it 404s
  end

  # get a list of docs from requested group 
  id_view = JSON.parse(RestClient.post("#{source_group}/_design/t/_view/byDKey", {}.to_json, :content_type => :json,:accept => :json ))
  $l.debug "Docs: #{id_view['rows'].length}"

  id_list = id_view['rows'].map { |row| row['id'] }

  id_list << "settings"
  id_list << "templates"
  id_list << "configuration"
  id_list << "_design/t"

  # replicate group to clean copied group
  replication_data = {
    :source  => "#{source_group}", 
    :target  => "#{copied_group}", # "copied-" because debugging on same server 
    :doc_ids => id_list,
    :create_target => true
  }.to_json

  
  replicate_request = RestClient.post($servers[:replicator], replication_data, :content_type => :json, :accept => :json)
  
  if ! ( replicate_request.code >= 200 && replicate_request.code < 300 )  
    halt_error(500, 'Database error: Could not create temp database.', 'Replication failed. Request data: #{replication_data}') 
  end

  # change the settings
  settings = JSON.parse(RestClient.get("#{copied_group}/settings"))
  
  settings.delete('adminEnsured')
  settings['context'] = "mobile"
  settings['log'] = []
  mobilfy_response = RestClient.put("#{copied_group}/settings", settings.to_json, :content_type => :json, :accept => :json)

  if !(mobilfy_response.code >= 200 && mobilfy_response.code < 300)
    halt_error(500, "Failed to prepare mobile database.", "Could not save settings for #{params[:group]}")
  end

  #
  # for the ojai-parallel, replicate into proper design doc
  #

  # See if one exists aready
  uri = URI($servers[:main] + "/db/copied-group-#{params[:group]}/_design/t")
  get_response = Net::HTTP.get_response(uri)
  if get_response.code == 200
    copy_rev = "?rev=" + JSON.parse(get_response.body).to_hash["_rev"]
  else
    copy_rev = ""
  end


  # @TODO
  # Add admin users from group to APK
  # download _security doc from group
  # get list of admins
  # look up each admin's _user doc
  # open Android-Couchbase-Callback's local.ini file
  # remove all the admins there except localadmin
  # save all admin users from the group like this:
  #  #{name} = -hashed-#{passwordSHA},#{passwordSalt}

  RestClient.post(File.join(copied_group, "_ensure_full_commit"), "", :content_type => 'application/json')
  $l.info "ensured full commit"


  begin

    # standardize all groups DBs here as tangerine.couch
    db_file     = "copied-group-#{params[:group]}.couch"
    group_db    = File.join( $couch_db_path, db_file )
    target_dir  = File.join( Dir.pwd, "Android-Couchbase-Callback", "assets" )

    target_path = File.join( target_dir, "t.couch" )

    # bring in the dog
    `rm #{target_path}`
    # put out the cat
    `ln -s #{group_db} #{target_path}`

  rescue Exception => e
   halt_error 500, "Failed to copy database.", "Could not copy #{params[:group]}'s database into assets. #{e}"
  end

  # upload assets
  $l.info "includeLessonPlans #{params[:includeLessonPlans]}"
  if params[:includeLessonPlans] == "true"
    begin
      asset_dir = File.join( Dir.pwd, "tutor-assets" )
      couchapprc_location = File.join( asset_dir, ".couchapprc"  )
      config_file = {
        "env" => {
          "default" => {
            "db" => "http://#{$username}:#{$password}@localhost:5984/copied-group-#{params[:group]}"
          }
        }
      }.to_json
      File.open( couchapprc_location, 'w' ) { |f| f.write(config_file) }
      $l.info "couchapp push"
      Dir.chdir(asset_dir) {
        `couchapp push`
      }
      $l.info "Done"

    rescue Exception => e
      halt_error 500, "Failed to upload lesson plan assets.", "Could not upload lesson plan assets. #{e}"
    end

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

    Dir.chdir(acc_dir) {
      `ant clean`
      `ant release`
      `mv bin/Tangerine-release.apk #{apk_path}`
    }

  rescue Exception => e
    halt_error 500, "Failed to prepare APK.", "Could not copy #{params[:group]}'s database into assets. #{e}"
  end
  
  return { :token => token }.to_json

end # post "/:group" do


get "/?:token?" do

  unless params[:token]
    return "<img src='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAAYElEQVQYV2NkIBIwEqmOAUWhYr/5f2SN9wtPwuXhDJCi89/uMBhyqTDAaJgmkAawQnSTYAqQNWBVCFIAAiDTYQCviRhWI3tgYqAC3EP56x9gegamGKYQWRFIDiMccSkEAA1HJ9daC7xxAAAAAElFTkSuQmCC'>" 
  end

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
    $l.debug "apk_path: #{apk_path}"
    halt_error 404, "No APK found, invalid token.", "(404) #{params[:token]}."
  end

end # of get "/:token" do

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
  $l.error "Couldn't make directory. #{e}"
end

def get_token()
  (1..6).map{|x| $character_set[rand($character_set.length)]}.join()
end

def mkdir(dir)
  name = File.join Dir::pwd, dir
  return nil if File.directory? name
  Dir::mkdir(name)
rescue Exception => e
  $l.error "Couldn't make directory. #{e}"
end

def halt_error(code, message, log_message)
  $l.error log_message
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
