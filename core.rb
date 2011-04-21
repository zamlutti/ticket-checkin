require 'sinatra'
require 'json'
require 'open-uri'
require 'hpricot'
require 'expense'
require 'oauth'

enable :sessions

get '/ticket_history' do
  number = params[:number]
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
  #puts expense_array[0].amount
  #haml :history
  doc  
end

def client
  OAuth::Consumer.new( "hxGukWgs3XLL1xU4tkrvPv7Fx11j5m0ZXtiyuGOv2Vo~","gAKi8cdPDF10VutPGhQsFzOrlAc~", {
      :site => "http://api.apontador.com.br", :http_method => :get, :scheme => :query_string, :request_token_path => '/v1/oauth/request_token', :authorize_path => '/v1/oauth/authorize', :access_token_path => '/v1/oauth/access_token'
      })
end

get '/auth/apontador' do
  request_token=client.get_request_token(:oauth_callback => redirect_uri)
  session[:request_token]=request_token
  redirect request_token.authorize_url
  
end

get '/apontador_callback' do
  request_token = session[:request_token]
  access_token=request_token.get_access_token
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
