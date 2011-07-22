require 'foursquare2'
require 'utils'
include Utils

module Foursquare
  
  def self.fixed_client
    @fixed_client ||= Foursquare2::Client.new(:client_id => FoursquareConfig.get_map['client_id'], 
    :client_secret => FoursquareConfig.get_map['client_secret'])
  end
  
  def self.perform_checkin user, venue_id, ll
    #:ll => '36.142064,-86.816086'
    client = Foursquare2::Client.new(:oauth_token => user['4sq_token'])
#    puts client.recent_checkins
    puts client.add_checkin(:venueId => venue_id, :broadcast => 'public', :ll => ll, :shout => 'Acabei de comer por aqui!')
  end
  
  def self.checkin user, location_name, ll
    if user['4sq_token']
      venue_id = find_place location_name, ll
      perform_checkin user, venue_id, ll
    end
  end
  
  def self.categories
    puts fixed_client.venue_categories
  end
  
  def self.find_place location_name, ll
    venue = fixed_client.search_venues(:query => location_name, :limit => 1, :ll => ll)
    if venue['groups'][0]['items'].length > 0
      venue['groups'][0]['items'][0]['id']
    else
      nil
    end
  end

  
end