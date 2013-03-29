
# $couch_db_path = "/usr/bin/couchdb" #File.join( `locate tangerine.couch`.split("\n")[0].split("/")[0..-2] )
$couch_db_path = "/var/lib/couchdb/1.2.0"
$username = ""
$password = ""
$servers = {
  :main  => "http://#{$username}:#{$password}@",
  :local => "http://#{$username}:#{$password}@",
  :robbert => "http://"
}
$main_http = Net::HTTP.new ""
