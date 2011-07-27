require 'foursquare2'
require 'utils'
include Utils

module Foursquare
  
  def self.fixed_client
    @fixed_client ||= Foursquare2::Client.new(:client_id => FoursquareConfig.get_map['client_id'], 
    :client_secret => FoursquareConfig.get_map['client_secret'], :ssl => { :verify => OpenSSL::SSL::VERIFY_PEER, :ca_file => '/usr/lib/ssl/certs/ca-certificates.crt' })
  end
  
  def self.perform_checkin token, venue_id, ll
    #:ll => '36.142064,-86.816086'
    client = Foursquare2::Client.new(:oauth_token => token, :ssl => { :verify => OpenSSL::SSL::VERIFY_PEER, :ca_file => '/usr/lib/ssl/certs/ca-certificates.crt' })
#    puts client.recent_checkins
    puts client.add_checkin(:venueId => venue_id, :broadcast => 'public,facebook,twitter', :ll => ll, :shout => 'Check-in via http://sanduicheck.in')
  end
  
  def self.checkin token, location_name, ll
      venue_id = find_place location_name, ll
      perform_checkin token, venue_id, ll if venue_id
  end
  
  def self.categories
    puts fixed_client.venue_categories
  end
  
  def self.find_place location_name, ll
    venue = fixed_client.search_venues(:query => location_name, :limit => 1, :ll => ll, :intent => 'match')
    if venue['groups'][0]['items'].length > 0
      venue['groups'][0]['items'][0]['id']
    else
      nil
    end
  end

  
end