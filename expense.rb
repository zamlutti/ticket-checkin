class Expense
  attr_accessor :date
  attr_accessor :description
  attr_accessor :amount
  
  def to_json(params=nil)
    "{\"expense\": {\"date\":\"#{@date}\",\"description\":\"#{@description}\", \"amount\" : \"#{@amount}\"}}"
  end
  
end