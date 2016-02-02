# coding: UTF-8
#
# Tangerine Tree
# This program generates APKs and a download link for a group.
#
# A cordova project submodule generates the APK.
# Files that contain bundles of json objects are stored as well and used by Tangerine
# during its first boot.
#

require "bundler"
Bundler.require

require_relative 'Token.rb'  # generates download tokens
require_relative 'halt_error.rb' # halts request and logs errors
require_relative 'config.rb' # usernames and urls

$l = Logger.new "tree.log"

#
# Constants
#

# how many documents are included in a pack file.
PACK_LIMIT = 50

# relative location to the init folder
INIT_FOLDER = File.join "Tangerine-client", "src", "js", "init" 

class Tree < Sinatra::Base


  #
  # Sinatra config
  #
  
  register Sinatra::CrossOrigin
  enable :cross_origin

  
  #set :allow_origin, :any
  #set :allow_methods, [:get, :post, :options]
  #set :allow_credentials, true
  
  configure do
    set :allow_origin, :any
    set :allow_methods, [:get, :post, :options]
    set :allow_credentials, true
    set :max_age, "1728000"
    set :protection, :except => :json_csrf
  end


  helpers Sinatra::Cookies
  # show a tree to show the app is working
  get "/" do
    "<img style='height:32px;width:32px;margin:auto;' src='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAl0lEQVQYV2NkgIKa1eX/n2jfZ1igtYoRJgaiwZzoM17/j645x2AdYsQAokEgxjieoSW0k5ERpvPN3ScMV47eQ9bM8KDjBSOjQoXEf5DOj88/wBW8P/yBQdBWAKwYbMKSswvBHJBE9h8BhmWOEPbHoz8YwW6AKYraz8DQdvIFWOz/////GUEA2dIqc4n/MAUwcQwFIAlkRQD1U0m4Go1m7gAAAABJRU5ErkJggg=='>"
  end

  #
  # handle a request to make an APK
  #

  post "/make/:group" do

    content_type :json

    #
    # verify contract requirements
    #

    auth_errors = []
    auth_errors << "a username" if params[:user] == nil
    #auth_errors << "a password" if params[:pass] == nil
    auth_errors << "a group"    if params[:group].length == 0

    halt_error(403, "User, and group required.", "Incomplete parameters") if auth_errors.length > 0


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

    # unique id for apks
    token = Token.make

    # url to group database
    source_group = "#{$servers[:main]}/group-#{params[:group]}"

    # default options for rest-client
    json_opts = { :content_type => :json, :accept => :json }

    #
    # create boot packs
    #


    # get a list of _ids for the assessments not archived
    assessments_view = JSON.parse(RestClient.post("#{source_group}/_design/ojai/_view/assessmentsNotArchived", {}.to_json, :content_type => :json, :accept => :json))
    list_query_data = assessments_view['rows'].map { |row| row['id'][-5..-1] }
    list_query_data = { "keys" => list_query_data }

    # get a list of files associated with those assessments
    id_view = JSON.parse(RestClient.post("#{source_group}/_design/ojai/_view/byDKey",list_query_data.to_json, json_opts ))
    id_list = id_view['rows'].map { |row| row['id'] }
    id_list << "settings"

    pack_number = 0 # start counter

    while id_list.length != 0

      ids = id_list.pop(PACK_LIMIT)

      docs_json = RestClient.post "#{source_group}/_all_docs?include_docs=true", {"keys" => ids}.to_json, json_opts
      docs = JSON.parse docs_json.force_encoding("UTF-8")

      doc_array = docs['rows'].map {|row| row['doc'] }

      file_name = "#{INIT_FOLDER}/pack%04d.json" % pack_number
      File.open(file_name, 'w') { |f| f.write({"docs"=>doc_array}.to_json) }

      pack_number += 1

    end

    current_dir = File.dirname(__FILE__)

    # make new directory for apk
    begin
      name = File.join current_dir, "apks", token
      Dir::mkdir(name)
    rescue Exception => e
      $l.error "Couldn't make directory. #{e}"
    end

    # in lieu of tracking apks properly, rely on the filesystem
    groupstamp_location = File.join( current_dir, "apks", token, params[:group] )
    `touch #{groupstamp_location}`

    # build APK
    begin
      client_dir = File.join current_dir, "Tangerine-client"
      $l.info client_dir
      $l.info `cd #{client_dir} && npm run build:apk`
    rescue Exception => e
      `rm #{INIT_FOLDER}/pack*.json`
      halt_error 500, "Failed to build APK.", "Could not build APK for #{params[:group]}. #{e}"
    end


    `rm #{INIT_FOLDER}/pack*.json`

    # move APK into token folder
    begin
      
      # crosswalk generates multiple apks, move them both
      apk_location = File.join current_dir, "Tangerine-client", "platforms", "android", "build", "outputs", "apk", "android-x86-debug.apk"
      apk_path = File.join current_dir, "apks", token, "tangerine-x86.apk"
      `mv #{apk_location} #{apk_path}`

      apk_location = File.join current_dir, "Tangerine-client", "platforms", "android", "build", "outputs", "apk", "android-armv7-debug.apk"
      apk_path = File.join current_dir, "apks", token, "tangerine-arm.apk"
      `mv #{apk_location} #{apk_path}`

    rescue Exception => e
      halt_error 500, "Failed to move APK.", "Could not move APK for #{params[:group]}. #{e}"
    end

    # output token
    $l.info token
    return { :token => token }.to_json

  end # post "/make/:group" do


  # download apk by token
  get "/apk/:token.?:format?" do


    # sanitize our parameters
    if params[:format] == "x86"
      format = "x86"
    elsif params[:format] == "arm"
      format = "arm"
    else
      format = "arm"
    end

    token = params[:token].downcase.gsub(/[^a-z]/,'')

    current_dir = File.dirname(__FILE__)

    apk_name = "tangerine-#{format}.apk"
    apk_path = File.join( current_dir, 'apks', token, apk_name)

    if File.exist? apk_path
      send_file( apk_path,
        :disposition => 'attachment',
        :filename    => File.basename(apk_name)
      )
    else
      content_type :json
      halt_error 404, "No APK found, invalid token.", "No APK file found at #{apk_path}."
    end

  end # of get "/apk/:token" do

end # of class Tree




