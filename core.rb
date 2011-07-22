require 'sinatra'
require 'json'
require 'open-uri'
require 'hpricot'
require 'expense'
require 'oauth'
require 'couchrest'
require 'utils'
require 'accor_ticket'
require 'visa_ticket'
require 'base64'
require 'hmac-sha1'
require 'rqrcode'
require 'qr_image'
require 'phone'
require 'qrcode'
require 'foursquare'
include Utils

#monkey_patch para put. Melhor colocar em classe externa

module OAuth::RequestProxy::Net
  module HTTP
    class HTTPRequest < OAuth::RequestProxy::Base
      def query_string
        params = [ query_params, auth_header_params ]
        params << post_params if
          ['POST', 'PUT'].include?(method.to_s.upcase)
        params.compact.join('&')
      end
    end
  end
end

enable :sessions

get '/ticket_history/:brand/:card_number' do
  number = params[:card_number]
  manager = Kernel.const_get "#{params[:brand].capitalize}ExpensesManager"
  expense_array = manager.get_expenses number
  #haml :history
  #expense_array[0]
  expense_array.to_json
end



get '/' do
  @consumer_key = ApontadorConfig.get_map['consumer_key']
  @callback_login = redirect_uri('/apontador_login_callback')
  @url = redirect_uri('/')
  encoder = HMAC::SHA1.new(ApontadorConfig.get_map['consumer_secret'])
  signature_base = "fc=#{@callback_login}&key=#{@consumer_key}&perms=api&url=#{@url}"
  @mysignature = URI.escape(Base64.encode64((encoder << signature_base).digest).strip).gsub('+', '%2B')
  haml :signup
end

post '/process_signup' do
  redirect '/' unless params[:card_number].length > 0
  session[:card_number] = params[:card_number].delete(' ')
  session[:card_type] = params[:card_type]
  request_token=client(:scheme => :query_string).get_request_token(:oauth_callback => redirect_uri)
  redirect request_token.authorize_url
end

get '/apontador_callback' do
  access_token=client(:scheme => :query_string).get_access_token(nil,:oauth_callback => redirect_uri, :oauth_verifier => params[:oauth_verifier])
  puts access_token.token
  puts access_token.secret
  response = access_token.get("http://#{ApontadorConfig.get_map['api_host']}/#{ApontadorConfig.get_map['api_sufix']}/users/self?type=json",{ 'Accept'=>'application/json' })
  user = JSON.parse(response.body)
  @db = get_db
  begin
    @mensagem = "#{user['user']['name']}, você acaba de registar seu vale/ticket da #{session[:card_type].capitalize} de número #{session[:card_number]} no sanduicheck.in. Agora é só usar o"
    @mensagem = @mensagem + " seu cartão e aguardar o check-in automático em seguida. Você pode retornar ao site e se logar para ver seu histórico e outras opções."
    @db.save_doc({'_id' => user['user']['id'], :type => 'user', :name => user['user']['name'], "#{session[:card_type]}_ticket".to_sym => session[:card_number], 
      :access_token => access_token.token, :access_secret => access_token.secret})
  rescue RestClient::Conflict => conflic
    doc = @db.get(user['user']['id'])
    doc['access_token'] = access_token.token
    doc['access_secret'] = access_token.secret
    doc["#{session[:card_type]}_ticket"] = session[:card_number]
    @db.save_doc(doc)
    @mensagem = "#{user['user']['name']}, você já havia registrado um ticket conosco. Ele acaba de ser atualizado para o vale/ticket da #{session[:card_type].capitalize} de número #{session[:card_number]} no sanduicheck.in."
  end
  haml :success
end


get '/apontador_login_callback' do
  
  encoder = HMAC::SHA1.new(ApontadorConfig.get_map['consumer_secret'])
  
  #Verifica assinatura
  signature_base = "consumerkey=#{params[:consumerkey]}&name=#{params[:name]}&token=#{params[:token]}&url=#{params[:url]}&userid=#{params[:userid]}"
  mysignature = Base64.encode64((encoder << signature_base).digest).strip
  raise Exception, "Assinatura inválida" unless mysignature == params[:signature]
  #realizar o check
  check_user response, params

end


get '/auto_checkin/:place_id' do
  raise Exception, "Sem place id" unless params[:place_id]
  auto_login request, params[:place_id]
end

get '/checkin/:place_id' do
  puts "---------------CHECKIN -------------"
  user = {'access_token' => session[:user]['oauth_token'], 'access_secret' => session[:user]['oauth_token_secret']}
  perform_checkin user, params[:place_id]
  "checkin efetuado com sucesso"
end

def auto_login request, place_id
  @url = redirect_uri("/checkin/#{place_id}")
  puts "-----------------AUTOLOGIN------------------------------"
  cookie = request.cookies["remember_me_token"]
  if cookie
    cookie_array = cookie.partition("|")
    puts "-----------------cookie------------------------------"
    check_user(response, :token => cookie_array[0], :userid => cookie_array[2], :url => @url)
  else
    @consumer_key = ApontadorConfig.get_map['consumer_key']
    @callback_login = redirect_uri('/apontador_login_callback')
    encoder = HMAC::SHA1.new(ApontadorConfig.get_map['consumer_secret'])
    signature_base = "fc=#{@callback_login}&key=#{@consumer_key}&perms=api&url=#{@url}"
    @mysignature = URI.escape(Base64.encode64((encoder << signature_base).digest).strip).gsub('+', '%2B')
    redirect "http://#{ApontadorConfig.get_map['auth_host']}/?key=#{@consumer_key}&perms=api&fc=#{@callback_login}&signature=#{@mysignature}&url=#{@url}"
  end
  
end

def check_user response, params
  
  encoder = HMAC::SHA1.new(ApontadorConfig.get_map['consumer_secret'])
  
  userid = params[:userid]
  token = params[:token]
  
  timestamp = Time.now.to_i
  signature_check_base = "key=#{ApontadorConfig.get_map['consumer_key']}&token=#{token}&ts=#{timestamp}&userid=#{userid}"
  signature_check = URI.escape(Base64.encode64((encoder << signature_check_base).digest).strip).gsub('+', '%2B')
  path_check = "/check?token=#{token}&userid=#{userid}&ts=#{timestamp}&key=#{ApontadorConfig.get_map['consumer_key']}&signature=#{signature_check}"
  url_check = 'http://'+ ApontadorConfig.get_map['auth_host'] + path_check
  puts url_check
  begin 
    f = open(url_check)
    api_response = f.read.gsub("'", "\"")
    puts api_response
    check_map = JSON.parse(api_response)
    #se for trusted terei email, token, token_secret adicionais
    response.set_cookie("remember_me_token", "#{token}|#{userid}")
    session[:user] = check_map
    puts "Foursquare: #{check_map['external_keys']['Foursquare']['oauth_token']}"
    begin
      @db = get_db
      doc = @db.get(userid)
      if doc
        doc['access_token'] = check_map['oauth_token']
        doc['access_secret'] = check_map['oauth_token_secret']
        doc['4sq_token'] = check_map['external_keys']['Foursquare']['oauth_token']
        @db.save_doc(doc)
      end
    rescue Exception => e
      puts e
    end
    redirect params[:url] if params[:url]
  rescue Exception => e
    puts e
  end
end

def checkin_all
  @db = get_db
  @db.view('users/all')['rows'].each do |row|
    user = row['value']
    puts user['name']
    checkin user
  end
end

private

  def client(params={})
    OAuth::Consumer.new(ApontadorConfig.get_map['consumer_key'],ApontadorConfig.get_map['consumer_secret'], {
        :site => 'http://' + ApontadorConfig.get_map['api_host'], :http_method => :get, :request_token_path => "/#{ApontadorConfig.get_map['api_sufix']}/oauth/request_token", :authorize_path => "/#{ApontadorConfig.get_map['api_sufix']}/oauth/authorize", :access_token_path => "/#{ApontadorConfig.get_map['api_sufix']}/oauth/access_token"
        }.merge(params))
  end

  def get_db
    couchdb_config = CouchDBConfig.get_map
    @db = CouchRest.database!("http://#{couchdb_config['user']}:#{couchdb_config['password']}@#{couchdb_config['host']}/#{couchdb_config['database']}")
  end

  
  def redirect_uri(path=nil)
    uri = URI.parse(request.url)
    uri.path = path || '/apontador_callback'
    uri.query = nil
    uri.to_s
  end
  
  def checkin user
    #@db = get_db
    #troque para testar. 0 para prod
    offset = 0
    ticket_number = user['accor_ticket'] || user['visa_ticket']
    brand = (user['accor_ticket']) ? 'Accor' : 'Visa'
    manager = Kernel.const_get "#{brand.capitalize}ExpensesManager"
    expense_array = manager.get_expenses ticket_number, lambda{ |expense| build_date(expense.date) == (Date.today - offset)}
    puts expense_array.length
    expense_array.each do |expense|
      expense_hash = JSON.parse(expense.to_json)['expense']
      begin
        if @db.view('unique_expenses/by_date_amount_and_desc', {'key' => [expense.date,expense.amount,expense.description]})['rows'].length == 0
          puts expense.to_json
          place_id = find_place expense.description
          if not place_id
            puts 'Não encontrado' + expense.description
            #TODO parametrizar multiplas cidades e estados
            synonyms = @db.view('synonyms/by_name_and_region', {'key' => [expense.description,'SP','São Paulo']})['rows']
            place_id = find_place synonyms.first['value']['synonym'] unless synonyms.empty?
          end
          if place_id
            perform_checkin(user, place_id)
            if user['4sq_token']
              begin
                ap_place = get_place place_id
                point = ap_place['place']['point']
                Foursquare.checkin(user, ap_place['place']['name'], "#{point['lat]'},#{point['lng']}")
              rescue Exception => e
                puts e
              end
            end
            @db.save_doc(expense_hash.merge(:type => 'expense', :ticket => ticket_number))  
          end
        end
      rescue Exception => e
        puts e
      end
    end
  end
  
  def find_place term
    #busca restaurante
    place_id = find_place_category term, 67
    #senao tenta lanchonete
    place_id ||= find_place_category term, 3  
  end
  
  def find_place_category term, category
    term = URI.escape term
    url = "http://#{ApontadorConfig.get_map['api_host']}/#{ApontadorConfig.get_map['api_sufix']}/search/places/byaddress?term=#{term}&state=sp&city=s%C3%A3o%20paulo&category_id=#{category}&type=json"
    f = open(url, :http_basic_authentication => [ApontadorConfig.get_map['consumer_key'], ApontadorConfig.get_map['consumer_secret']])
    obj = JSON.parse f.read
    if (obj['search']['result_count'].to_i > 0 )
      place_id = obj['search']['places'][0]['place']['id'].to_s
    end
  end
  
  def get_place place_id
    url = "http://#{ApontadorConfig.get_map['api_host']}/#{ApontadorConfig.get_map['api_sufix']}/places/#{place_id}?type=json"
    f = open(url, :http_basic_authentication => [ApontadorConfig.get_map['consumer_key'], ApontadorConfig.get_map['consumer_secret']])
    JSON.parse f.read
  end
  
  def perform_checkin(user, place_id)
    access_token = OAuth::AccessToken.new(client(:scheme => :body, :method => :put), user['access_token'], user['access_secret'])
    response = access_token.put("http://#{ApontadorConfig.get_map['api_host']}/#{ApontadorConfig.get_map['api_sufix']}/users/self/visits",{:type => 'json', :place_id => place_id}, {'Accept'=>'application/json' })
    result = JSON.parse(response.body)
  end
  