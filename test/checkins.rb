require 'core'
require 'YAML'

@db = get_db
user = @db.get('2164744031')
perform_checkin(user,'M25GJ288')
#puts @db.view('unique_expenses/by_date_amount_and_desc')['rows']