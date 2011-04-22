require 'lib/config_store'

module Utils
  
  def build_date (date_str)
    dia = date_str[0..1].to_i
    mes = date_str[3..4].to_i
    ano = date_str[6..9].to_i
    Date.civil(ano,mes,dia)
  end
  
  class ApontadorConfig
    
    def self.get_map
      @@apontador_config ||= ConfigStore.new("config/apontador_credentials.yml")
    end
    
  end
 
end