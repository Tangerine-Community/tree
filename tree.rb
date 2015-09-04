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

require "bundler"
Bundler.require

require './config.rb'

$logger = Logger.new "tree.log"

#
# Sinatra config
#

set :allow_origin, :any
set :allow_methods, [:get, :post, :options]
set :allow_credentials, true
set :max_age, "1728000"
set :protection, :except => :json_csrf


#
# Constants
#

# how many documents are included in a pack file.
PACK_LIMIT = 50

# how long the download token is
TOKEN_LENGTH = 6

# this character set is used to create a token that will be used to download
# an APK. We assumed that the token will be entered by a human using a mobile
# devices' keyboard. To expedite entry, only lower case it used and no numbers.
# To eliminate human error the chracters below omit
# omitted  | looks like
#  l           I, 1
#  f           t
#  q           g
#  j           i

$character_set = "abcdeghikmnoprstuwxyz".split("")


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

  #
  # create boot packs
  #

  json_opts = { :content_type => :json, :accept => :json }

  # get a list of _ids for the assessments not archived
  assessments_view = JSON.parse(RestClient.post("#{source_group}/_design/ojai/_view/assessmentsNotArchived", {}.to_json, :content_type => :json, :accept => :json))
  list_query_data = assessments_view['rows'].map { |row| row['id'][-5..-1] }
  list_query_data = { "keys" => list_query_data }

  # get a list of files associated with those assessments
  id_view = JSON.parse(RestClient.post("#{source_group}/_design/ojai/_view/byDKey",list_query_data.to_json, json_opts ))
  id_list = id_view['rows'].map { |row| row['id'] }
  id_list << "settings"

  # start counter
  pack_number = 0
  while id_list.length != 0

    ids = id_list.pop(PACK_LIMIT)

    docs = JSON.parse RestClient.get "#{source_group}/_all_docs?include_docs=true&keys=#{ids.to_json}"
    doc_array = docs['rows'].map {|row| row['doc'] }

    file_name = "pack%04d.json" % pack_number
    File.open(file_name, 'w') { |f| f.write({"docs"=>doc_array}.to_json) }

    pack_number += 1

  end


  current_dir = Dir.pwd

  # make new directory for apk
  ensure_dir current_dir, "apks", token

  # in lieu of tracking apks properly, rely on the filesystem
  groupstamp_location = File.join( current_dir, "apks", token, params[:group] )
  `touch #{groupstamp_location}`

  # build APK
  begin
    client_dir = File.join Dir.pwd, "Tangerine-client"
    Dir.chdir(client_dir) {
      `npm run build:apk`
    }
  rescue Exception => e
    halt_error 500, "Failed to build APK.", "Could not build APK for #{params[:group]}. #{e}"
  end

  # move APK into token folder
  begin
    apk_location = File.join "platforms", "android", "build", "outputs", "apk", "android-x86-debug.apk"
    apk_path = File.join current_dir, "apks", token, "tangerine.apk"
    `mv #{apk_location} #{apk_path}`
  rescue Exception => e
    halt_error 500, "Failed to move APK.", "Could not move APK for #{params[:group]}. #{e}"
  end

  # output token
  return { :token => token }.to_json

end # post "/make/:group" do


# download apk by token
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
  (1..TOKEN_LENGTH).map{|x| $character_set[rand($character_set.length)]}.join()
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
