require 'rubygems'
require 'json'
require 'open-uri'
require 'hpricot'
require 'expense'

def get_visa_expenses number
    url = "http://www.cbss.com.br/inst/convivencia/SaldoExtrato.jsp?numeroCartao=#{number}&primeiroAcesso=S"
    f = open(url)
    #f = File.open('mock_visa.html')
    doc = Hpricot(Iconv.conv('UTF-8', f.charset, f.read))
    #doc = Hpricot(f)
    doc = doc.search("body/form/table")
    i = 0
    expense_array = Array.new
    expense = Expense.new
    doc[2].search("tr/td").each do |elem|
      if i == 0 
        expense.date = "#{elem.inner_html}/#{Time.now.year}"
      elsif i == 1
        expense.description = elem.inner_html
      elsif i == 2
        expense.amount = elem.inner_html.delete('R$&nbsp;')  
        expense_array.push(expense)
        expense = Expense.new
      end
      i = (i+1) % 3
    end
    expense_array
end