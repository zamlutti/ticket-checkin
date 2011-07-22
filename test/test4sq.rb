require 'foursquare'
require 'YAML'

user = {'4sq_token'=>'xxxxxxxxxxxxxx'}

ap = Foursquare.checkin(user['4sq_token'], 'apontador', '-23.592228,-46.686777')
