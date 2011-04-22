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
      expense_array << expense
    else
      puts 'ignoring: '+elem.to_s
    end
  end
  #haml :history
  #expense_array[0]
  history_array.to_json
end

def client
  OAuth::Consumer.new(ApontadorConfig.get_map['consumer_key'],ApontadorConfig.get_map['consumer_secret'], {
      :site => "http://api.apontador.com.br", :http_method => :get, :scheme => :query_string, :request_token_path => '/v1/oauth/request_token', :authorize_path => '/v1/oauth/authorize', :access_token_path => '/v1/oauth/access_token'
      })
end

get '/auth/apontador' do
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
  puts response
  obj = JSON.parse(response.body)
  response.body
end

get '/test_call' do
  access_token = OAuth::AccessToken.new(client, '2164744031-hxGukWgs3XK1KxSV6iyRkofC-YvNPw7Do3euGYDuwfqTRC1HwJmFyQ~~', 'UACOgiWO8vn7AaeV1Nn_l_C-o1w~')
  response = access_token.get('http://api.apontador.com.br/v1/users/self?type=json',{ 'Accept'=>'application/xml' })
  puts response
  obj = JSON.parse(response.body)
  response.body
end


get '/couch' do
  @db = CouchRest.database!("http://tickets:tickets@127.0.0.1:5984/ticket-checkin")
#  response = @db.save_doc({'_id' => '1234', :name => 'thiago'})
  doc = @db.get('1234')
  puts build_date('12/04/2011')
  puts 
  puts doc.inspect
  'funfou'
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


  def redirect_uri
    uri = URI.parse(request.url)
    uri.path = '/apontador_callback'
    uri.query = nil
    uri.to_s
  end
