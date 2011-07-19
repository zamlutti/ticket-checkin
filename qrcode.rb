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
    @url = create_image_url params[:place_id], params[:size]
    haml :qrcode_img
end

get '/qrcode/:place_id' do
    @url = create_image_url params[:place_id]
    haml :qrcode_img
end

get '/baboo' do
  generate_pdf
end

def generate_pdf path=nil
  PDFKit.configure do |config|
    config.wkhtmltopdf = "#{File.dirname(__FILE__)}/wkhtmltopdf-amd64"
  end
  content_type 'application/pdf', :charset => 'utf-8'
  kit = PDFKit.new('http://sanduicheck.in/qrcode/xxxx')
  pdf = kit.to_pdf

end

def create_image_url place_id, size_code=nil
  if (not size_code) || (size_code == 'P')
    size = 6
  elsif size_code == 'M'
    size = 8
  elsif size_code == 'G'
    size = 12
  else 
    raise Exception, "Erro tamanho"
  end
  redirect_uri("/qrcode_img/#{place_id}/#{size}")
end
