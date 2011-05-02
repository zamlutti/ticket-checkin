require 'rubygems'
require 'open-uri'
require 'hpricot'
require 'expense'
require 'json'

class AccorExpensesManager

  class << self
    
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
  end
end