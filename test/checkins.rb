require 'core'
require 'YAML'

@db = get_db
puts @db.view('unique_expenses/by_date_amount_and_desc')['rows']