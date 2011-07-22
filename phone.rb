
get '/add_phone' do
  haml :phone
end

get '/to_verify' do
  phone = params[:phone].to_i
  verifier = '#'+(Time.now+rand*10**10+phone).to_i().to_s(36).upcase
  @db = get_db
  doc = @db.get(session[:user]['userid'])
  doc['phone'] = '+55'+phone.to_s
  doc['phone_verifier'] = verifier
  @db.save_doc(doc)
  verifier
end

FAIL_PAYLOAD = " {
      \"payload\": {
        \"success\": \"false\"
    }
} "

SUCCESS_PAYLOAD = "
       {
             \"payload\": {
               \"success\": \"true\"
           }
       } "

def verify params
  
  received_verifier = params[:message].upcase
    
  from = params[:from]
  @db = get_db
  begin
    puts from
    result = @db.view('users/by_phone', {'key' => [from]})['rows']
    if result.size > 0
      user = result[0]['value']
      if user['phone_verifier'] == received_verifier
        user['phone_verifier'] = nil
        @db.save_doc(user)
      end
    end
  rescue Exception => e
    puts e
  end
  SUCCESS_PAYLOAD 
end


post '/sms_gtw' do

  if (params[:secret] != 'cld!5cTgsas')
    return FAIL_PAYLOAD
  end
  if params[:message] =~ /#.+/
    return verify params
  end
  from = params[:from]
  lbsid = params[:message]
  lbsid.strip!
  @db = get_db
  begin
    result = @db.view('users/by_phone', {'key' => [from]})['rows']
    if result.size > 0
      user = result[0]['value']
      perform_checkin user, lbsid unless user['phone_verifier']
    end
  rescue Exception => e
    puts e
  end
  puts "----------"
  puts lbsid
  puts from
  SUCCESS_PAYLOAD
end