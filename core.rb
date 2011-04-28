require 'sinatra'
require 'json'
require 'open-uri'
require 'hpricot'
require 'expense'
require 'oauth'
require 'couchrest'
require 'utils'
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

get '/ticket_history/:ticket_number' do
  number = params[:ticket_number]
  expense_array = get_expenses number
  #haml :history
  #expense_array[0]
  expense_array.to_json
end

get '/' do
  haml :signup
end

post '/process_signup' do
  session[:ticket_number] = params[:ticket_number]
  request_token=client(:scheme => :query_string).get_request_token(:oauth_callback => redirect_uri)
  redirect request_token.authorize_url
end

get '/apontador_callback' do
  access_token=client(:scheme => :query_string).get_access_token(nil,:oauth_callback => redirect_uri, :oauth_verifier => params[:oauth_verifier])
  puts access_token.token
  puts access_token.secret
  response = access_token.get('http://api.apontador.com.br/v1/users/self?type=json',{ 'Accept'=>'application/json' })
  user = JSON.parse(response.body)
  puts user['user']['id']
  puts user['user']['name']
  @db = get_db
  begin
    @db.save_doc({'_id' => user['user']['id'], :type => 'user', :name => user['user']['name'], :ticket => session[:ticket_number], 
      :access_token => access_token.token, :access_secret => access_token.secret})
  rescue RestClient::Conflict => conflic
    doc = @db.get(user['user']['id'])
    doc['access_token'] = access_token.token
    doc['access_secret'] = access_token.secret
    doc['ticket'] = session[:ticket_number]
    @db.save_doc(doc)
    return 'Usuário já cadastrado! Atualizando'
  end
  'Usuário cadastrado com sucesso!'
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
        :site => "http://api.apontador.com.br", :http_method => :get, :request_token_path => '/v1/oauth/request_token', :authorize_path => '/v1/oauth/authorize', :access_token_path => '/v1/oauth/access_token'
        }.merge(params))
  end

  def get_db
    couchdb_config = CouchDBConfig.get_map
    @db = CouchRest.database!("http://#{couchdb_config['user']}:#{couchdb_config['password']}@#{couchdb_config['host']}/#{couchdb_config['database']}")
  end

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
      index =  descricao =~ /COMPRA -|COMPRAS -/
      if index
        expense = Expense.new
        expense.description = descricao[(Regexp.last_match(0).length + 1)..descricao.length]
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
  
  def checkin user
    #@db = get_db
    #troque para testar. 0 para prod
    offset = 0
    expense_array = get_expenses user['ticket'], lambda{ |expense| build_date(expense.date) == (Date.today - offset)}
    puts expense_array.length
    expense_array.each do |expense|
      expense_hash = JSON.parse(expense.to_json)['expense']
      begin
        if @db.view('unique_expenses/by_date_amount_and_desc', {'key' => [expense.date,expense.amount,expense.description]})['rows'].length == 0
          puts expense.to_json
          place_id = find_place expense.description
          if not place_id
            #TODO parametrizar multiplas cidades e estados
            synonyms = @db.view('synonyms/by_name_and_region', {'key' => [expense.description,'SP','São Paulo']})['rows']
            place_id = find_place synonyms.first['value']['synonym'] unless synonyms.empty?
          end
          if place_id
            perform_checkin(user, place_id)
            @db.save_doc(expense_hash.merge(:type => 'expense', :ticket => user['ticket']))  
          end
        end
      rescue Exception => e
        puts e
      end
    end
  end
  
  def find_place term
    term = URI.escape term
    url = "http://api.apontador.com.br/v1/search/places/byaddress?term=#{term}&state=sp&city=s%C3%A3o%20paulo&category_id=67&type=json"
    f = open(url, :http_basic_authentication => [ApontadorConfig.get_map['consumer_key'], ApontadorConfig.get_map['consumer_secret']])
    obj = JSON.parse f.read
    if (obj['search']['result_count'].to_i > 0 )
      place_id = obj['search']['places'][0]['place']['id'].to_s
    end
  end
  
  def perform_checkin(user, place_id)
    access_token = OAuth::AccessToken.new(client(:scheme => :body, :method => :put), user['access_token'], user['access_secret'])
    response = access_token.put('http://api.apontador.com.br/v1/users/self/visits',{:type => 'json', :place_id => place_id}, {'Accept'=>'application/json' })
    result = JSON.parse(response.body)
  end
  