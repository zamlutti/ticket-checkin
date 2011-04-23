require 'sinatra'
require 'json'
require 'open-uri'
require 'hpricot'
require 'expense'
require 'oauth'
require 'couchrest'
require 'utils'

include Utils

enable :sessions

get '/ticket_history/:ticket_number' do
  number = params[:ticket_number]
  expense_array = get_expenses number
  #haml :history
  #expense_array[0]
  expense_array.to_json
end


def client
  OAuth::Consumer.new(ApontadorConfig.get_map['consumer_key'],ApontadorConfig.get_map['consumer_secret'], {
      :site => "http://api.apontador.com.br", :http_method => :get, :scheme => :query_string, :request_token_path => '/v1/oauth/request_token', :authorize_path => '/v1/oauth/authorize', :access_token_path => '/v1/oauth/access_token'
      })
end

def get_db
  couchdb_config = CouchDBConfig.get_map
  @db = CouchRest.database!("http://#{couchdb_config['user']}:#{couchdb_config['password']}@#{couchdb_config['host']}/#{couchdb_config['database']}")
end

get '/signup' do
    haml :signup
end

post '/process_signup' do
  session[:ticket_number] = params[:ticket_number]
  request_token=client.get_request_token(:oauth_callback => redirect_uri)
  session[:request_token]=request_token
  redirect request_token.authorize_url
end

get '/apontador_callback' do
  request_token = session[:request_token]
  access_token=client.get_access_token(request_token, :oauth_verifier => params[:oauth_verifier])
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
    return 'Usuário já cadastrado!'
  end
  response.body
end

get '/test_call' do
  access_token = OAuth::AccessToken.new(client, '2164744031-hxGukWgs3XK1KxSV6iyRkofC-YvNPw7Do3euGYDuwfqTRC1HwJmFyQ~~', 'UACOgiWO8vn7AaeV1Nn_l_C-o1w~')
  response = access_token.get('http://api.apontador.com.br/v1/users/self?type=json',{ 'Accept'=>'application/xml' })
  puts response
  obj = JSON.parse(response.body)
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
