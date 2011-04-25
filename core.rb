require 'sinatra'
require 'json'
require 'open-uri'
require 'hpricot'
require 'expense'
require 'oauth'
require 'couchrest'
require 'utils'
include Utils

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


use Rack::Session::Cookie, :key => 'tickets.session',
                           :path => '/',
                           :expire_after => 2592000, # In seconds
                           :secret => 'baboo'

get '/ticket_history/:ticket_number' do
  number = params[:ticket_number]
  expense_array = get_expenses number
  #haml :history
  #expense_array[0]
  expense_array.to_json
end


def client(params={})
  OAuth::Consumer.new(ApontadorConfig.get_map['consumer_key'],ApontadorConfig.get_map['consumer_secret'], {
      :site => "http://localhost:8080", :http_method => :get, :request_token_path => '/freeapi/oauth/request_token', :authorize_path => '/freeapi/oauth/authorize', :access_token_path => '/freeapi/oauth/access_token'
      }.merge(params))
end

def get_db
  couchdb_config = CouchDBConfig.get_map
  @db = CouchRest.database!("http://#{couchdb_config['user']}:#{couchdb_config['password']}@#{couchdb_config['host']}/#{couchdb_config['database']}")
end


get '/signup' do
  puts session[:ticket_number]
  haml :signup
end

post '/process_signup' do
  session[:ticket_number] = params[:ticket_number]
  request_token=client(:scheme => :query_string).get_request_token(:oauth_callback => redirect_uri)
  redirect request_token.authorize_url
end

get '/apontador_callback' do
  request_token = OAuth::RequestToken.new(client(:scheme => :query_string), session[:request_token],session[:request_token_secret])
  access_token=client(:scheme => :query_string).get_access_token(nil,:oauth_callback => redirect_uri, :oauth_verifier => params[:oauth_verifier])
  puts access_token.token
  puts access_token.secret
  response = access_token.get('http://api.apontador.com.br/v1/users/self?type=json',{ 'Accept'=>'application/xml' })
  user = JSON.parse(response.body)
  puts user['user']['id']
  puts user['user']['name']
  @db = get_db
  begin
    @db.save_doc({'_id' => user['user']['id'], :type => 'user', :name => user['user']['name'], :ticket => session[:ticket_number], 
      :access_token => access_token.token, :access_secret => access_token.secret})
  rescue RestClient::Conflict => conflic
    @db.update_doc(user['user']['id']) {|doc| (doc['access_token'] = access_token.token) && (doc['access_secret'] = access_token.secret)}
    return 'Usuário já cadastrado! Atualizando'
  end
  'Usuário cadastrado com sucesso!'
end

get '/test_call' do
  @db = get_db
  doc = @db.get('2164744031')
  puts "#{doc['access_token']} ------ #{doc['access_secret']}"
  access_token = OAuth::AccessToken.new(client(:scheme => :query_string), doc['access_token'], doc['access_secret'])
  response = access_token.get('http://api.apontador.com.br/v1/users/self?type=json',{ 'Accept'=>'application/json' })
  puts response
  obj = JSON.parse(response.body)
  response.body
end

get '/test_find' do
  term = URI.escape 'patroni pizza vila olimpia'
  url = "http://api.apontador.com.br/v1/search/places/byaddress?term=#{term}&state=sp&city=s%C3%A3o%20paulo&category_id=67&type=json"
  f = open(url, :http_basic_authentication => [ApontadorConfig.get_map['consumer_key'], ApontadorConfig.get_map['consumer_secret']])
  obj = JSON.parse f.read
  if (obj['search']['result_count'].to_i > 0 )
    place_id = obj['search']['places'][0]['place']['id'].to_s
  end
  place_id
end

get '/test_checkin' do
  @db = get_db
  place_id = 'C40619741C415O415A'
  doc = @db.get('2164744031')
  puts "#{doc['access_token']} ------ #{doc['access_secret']}"
  access_token = OAuth::AccessToken.new(client(:scheme => :body, :method => :put), doc['access_token'], doc['access_secret'])
  response = access_token.put('http://localhost:8080/freeapi/users/self/visits',{:type => 'json', :place_id => place_id}, {'Accept'=>'application/json' })
  response.body
end

get '/test_checkin_gambi' do
  @db = get_db
  place_id = 'C40619741C415O415A'
  doc = @db.get('2164744031')
  puts "#{doc['access_token']} ------ #{doc['access_secret']}"
  access_token = OAuth::AccessToken.new(client(:scheme => :body), doc['access_token'], doc['access_secret'])
  response = access_token.put('http://localhost:8080/freeapi/users/self/visits',{:type => 'json', :place_id => place_id}.merge(params), {'Accept'=>'application/json' })
  response.body
end

get '/couch_test' do
  @db = get_db
#  response = @db.save_doc({'_id' => '1234', :name => 'thiago'})
  doc = @db.get('1234')
  puts build_date('12/04/2011')
  puts 
  puts doc.inspect.class
  'funfou'
end

get '/checkin/:ticket_number' do
  @db = get_db
  number = params[:ticket_number]
  #troque para testar. 0 para prod
  offset = 3
  expense_array = get_expenses number, lambda{ |expense| build_date(expense.date) == (Date.today - offset)}
  expense_array.each do |expense|
    expense_hash = JSON.parse(expense.to_json)['expense']
    begin
      @db.save_doc(expense_hash.merge(:type => 'expense', :ticket => number))
    rescue Exception => e
      puts e
    end
  end
  ''
end

private
  def get_doc operation, number
    url = "http://www.ticket.com.br/portal/portalcorporativo/dpages/service/consulteseusaldo/seeBalance.jsp?txtOperation=#{operation}&txtCardNumber=#{number}"
    begin
      puts url
      f = open(url)
      #f = File.open('mock.txt')
      doc = Hpricot(Iconv.conv('UTF-8', f.charset, f.read))
      #doc = Hpricot(f)
      doc = doc.at("body/script").inner_html
      initial_index = doc =~ /\[/
      final_index = doc =~ /\]/
      doc = doc[initial_index..final_index]
      doc = doc.gsub("descricao", "\"descricao\"")
      doc = doc.gsub("data", "\"data\"")
      doc = doc.gsub("valor", "\"valor\"")
      doc = doc.gsub("'", "\"")
    rescue => e
      return [503,"Erro: #{e}"]
    end
  end

  def get_expenses number, filter=nil
    operation = 'lancamentos'
    doc = get_doc operation,number
    history_array = JSON.parse(doc)
    expense_array = Array.new
    history_array.each do |elem|
      descricao = elem['descricao']
      index =  descricao =~ /COMPRAS -/
      if index
        expense = Expense.new
        expense.description = descricao[10..descricao.length]
        expense.date = elem['data']
        expense.amount = elem['valor']
        return expense_array if (filter && (not filter.call(expense)))
        expense_array << expense
      else
        puts 'ignoring: '+elem.to_s
      end
    end
    expense_array
  end

  def redirect_uri
    uri = URI.parse(request.url)
    uri.path = '/apontador_callback'
    uri.query = nil
    uri.to_s
  end
