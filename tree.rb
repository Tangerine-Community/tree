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
$couch_db_path = File.join( `locate tangerine.couch`.split("\n")[0].split("/")[0..-2] )

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

  puts "sending: #{params[:group]}"

  #
  # Authenticate user for the group
  #
  auth_response = RestClient.post "http://localhost:82", { 
    :action => "am_admin", 
    :group  => params[:group], 
    :user   => params[:user] }
  halt_error(403, "Sorry, you have to be an admin within the group to make an APK.") if JSON.parse(auth_response.body)["message"] == "no"

  #
  # Make APK, place it in token-directory for download
  #

  token = get_token()

  id_view = JSON.parse(RestClient.post("http://tree:treepassword@tangerine.iriscouch.com/group-#{params[:group]}/_design/ojai/_view/byDKey", {}.to_json, :content_type => :json, :accept => :json))
  id_list = id_view['rows'].map { |row| row['id'] }

  puts "sending this"
  puts({ :source  => "http://tree:treepassword@tangerine.iriscouch.com/group-#{params[:group]}", 
    :target  => "copied-group-#{params[:group]}", # "copied-" because debugging on same server 
    :doc_ids => id_list,
    :create_target => true
  }.to_json)

  # replicate group to new local here
  replicate_response = RestClient.post("http://tree:treepassword@localhost:5984/_replicate", {
    :source  => "http://tree:treepassword@tangerine.iriscouch.com/group-#{params[:group]}", 
    :target  => "copied-group-#{params[:group]}", # "copied-" because debugging on same server 
    :doc_ids => id_list,
    :create_target => true
  }.to_json, :content_type => :json )

  settings = JSON.parse(RestClient.get("http://tree:treepassword@localhost:5984/copied-group-#{params[:group]}/settings"))
  settings['context'] = "mobile"
  mobilfy_response = RestClient.put("http://tree:treepassword@localhost:5984/copied-group-#{params[:group]}/settings", settings.to_json, :content_type => :json, :accept => :json)
  puts mobilfy_response


  halt_error 500, "Failed to replicate to tree." if replicate_response.code != 200

  #
  # for the ojai-parallel, replicate into proper design doc
  #

  # See if one exists aready
  http = Net::HTTP.new "localhost", 5984
  get_request = Net::HTTP::Get.new("/copied-group-#{params[:group]}/_design/tangerine")
  get_response = http.request get_request
  if get_response.code.to_i == 200
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

  # copy _design/ojai to _design/tangerine
  copy_request = Net::HTTP::Copy.new("/copied-group-#{params[:group]}/_design/ojai")
  copy_request["Destination"] = "_design/tangerine" + copy_rev
  copy_request.basic_auth "tree", "treepassword"
  copy_response = http.request copy_request

  copy_code = copy_response.code.to_i
  halt_error 500, "Tree's couch failed to rename design doc." if !(copy_code >= 200 && copy_code < 300)

  begin
    # clear out temp dir if it's there
    blank_dir = File.join( Dir.pwd, "tangerine" )
    `rm -rf #{blank_dir}`

    # make a new temporary dir
    tangerine_apk = File.join( Dir.pwd, "tangerine.zip" )
    `unzip #{tangerine_apk}`

    # standardize all groups DBs here as tangerine.couch
    db_file     = "copied-group-#{params[:group]}.couch"
    group_db    = File.join( $couch_db_path, db_file )
    target_dir  = File.join( Dir.pwd, "Android-Couchbase-Callback", "assets" )
    puts "putting into #{target_dir}"
    target_path = File.join( target_dir, "tangerine.couch" )
    `cp #{group_db} #{target_path}`

    # rename database (I think this is the only way)
    old_database = File.join target_dir, db_file
    new_database = File.join target_dir, "tangerine.couch"
    "mv #{old_database} #{new_database}"

  rescue Exception => e
    $logger.error "Could not copy #{params[:group]}'s database into assets. #{e}"
    halt_error 500, "Failed to copy database."
  end

  
  # zip APK and place it in token download directory
  begin


    puts "starting "
    current_dir = Dir.pwd
    ensure_dir current_dir, "apks", token

    groupstamp_location = File.join( current_dir, "apks", token, params[:group] )
    `touch #{groupstamp_location}`

    acc_dir = File.join Dir.pwd, "Android-Couchbase-Callback"
    assets_dir = File.join Dir.pwd, "Android-Couchbase-Callback", "assets"
    puts "\n\n\n #{acc_dir}"
    apk_path = File.join( current_dir, "apks", token, "tangerine.apk" )

    Dir.chdir(acc_dir) {
      puts "clean"
      puts `ant clean`
      puts "debug"
      puts `ant debug`
      puts "moving"
      puts `mv bin/Tangerine-debug.apk #{apk_path}`
    }
    

  rescue Exception => e
    $logger.error "Could not copy #{params[:group]}'s database into assets. #{e}"
    halt_error 500, "Failed to prepare APK."
  end
  
  return { :token => token }.to_json

end # post "/make/:group" do


get "/apk/:token" do

  cross_origin

  content_type :json

  current_dir = Dir.pwd

  apk_name = "tangerine.apk"
  apk_path = File.join( current_dir, 'apks', params[:token], apk_name)

  if File.exist? apk_path
    send_file( apk_path ,
      :disposition => 'attachment', 
      :filename    => File.basename(apk_name)
    )
  else
    $logger.warn "(404) params[:token]."
    halt_error 404, "No APK found, invalid token."
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

def halt_error(code, message)
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
