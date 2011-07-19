require 'pdfkit'

get '/qrcode_table/:place_id' do
   @qr = RQRCode::QRCode.new(redirect_uri("/auto_checkin/#{params[:place_id]}"), :level => :q)
   haml :qrcode_table
end

get '/qrcode_img/:place_id/:size' do
  qr = RQRCode::QRCode.new(redirect_uri("/auto_checkin/#{params[:place_id]}"), :size => 5, :level => :q)
  img = QRImage.new(qr).sample(params[:size].to_f)
  img.to_blob
end

get '/qrcode/:place_id/:size' do
    @url = create_url 'qrcode_img', params[:place_id], params[:size]
    @url_pdf =  redirect_uri("/pdf/#{params[:place_id]}/#{params[:size]}")
    @code = params[:place_id]
    @size = convert_size_code params[:size]
    @place = get_place params[:place_id]
    haml :qrcode_img
end

get '/qrcode/:place_id' do
    @url = create_url 'qrcode_img', params[:place_id]
    @url_pdf =  redirect_uri("/pdf/#{params[:place_id]}/M")
    @code = params[:place_id]
    @size = convert_size_code
    @place = get_place params[:place_id]
    haml :qrcode_img
end

get '/pdf/:place_id/:size' do
  generate_pdf params[:place_id], params[:size]
end

def generate_pdf place_id, size
  PDFKit.configure do |config|
    config.wkhtmltopdf = "#{File.dirname(__FILE__)}/wkhtmltopdf-amd64"
  end
  content_type 'application/pdf', :charset => 'utf-8'
  kit = PDFKit.new("http://ticket-checkin-clone.heroku.com/qrcode/#{place_id}/#{size}")
  pdf = kit.to_pdf

end

def create_url prefix, place_id, size_code=nil
  if (size_code == 'P')
    size = 6
  elsif (not size_code) || (size_code == 'M')
    size = 8
  elsif size_code == 'G'
    size = 12
  else 
    raise Exception, "Erro tamanho"
  end
  redirect_uri("/#{prefix}/#{place_id}/#{size}")
end

def convert_size_code size_code=nil
  if (size_code == 'P')
    return 1.0
  elsif (not size_code) || (size_code == 'M')
    return 2.0
  elsif size_code == 'G'
    return 3.0
  else 
    raise Exception, "Erro tamanho"
  end
end
