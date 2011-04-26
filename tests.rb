
get '/test_find' do
  find_place 'patroni pizza vila olimpia'
end

get '/checkins' do
  @db = get_db
  doc = @db.get('2164744031')
  puts "#{doc['access_token']} ------ #{doc['access_secret']}"
  access_token = OAuth::AccessToken.new(client(:scheme => :query_string), doc['access_token'], doc['access_secret'])
  response = access_token.get('http://api.apontador.com.br/v1/users/self/visits?type=json',{'Accept'=>'application/json' })
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

get '/test/query' do
  @db = get_db
  @db.view('unique_expenses/by_date_amount_and_desc', {'key' => ['25/04/2011','14,30',"SAUIPE CAFE E LANCHES LTDA"]})['rows'].length.to_s
end