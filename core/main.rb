require 'mini_magick'
require 'json'
require 'httparty'

class BasicConstants
  loaded_settings = File::open('/currency-bot/data/settings.json')
  loaded_settings = JSON::load(loaded_settings)

  TOKEN = loaded_settings['main']['token']
  GROUP = loaded_settings['main']['group_id']
  API     = 'https://api.vk.com/method/'
  VERSION = '5.103'

  URL_GET_LONGPOLL             = "#{API}groups.getLongPollServer?v=#{VERSION}&access_token=#{TOKEN}&group_id=#{GROUP}"
  SEND_MESSAGE                 = "#{API}messages.send?v=#{VERSION}&random_id=0&access_token=#{TOKEN}"
  GET_ATTACHMENT_UPLOAD_SERVER = "#{API}photos.getMessagesUploadServer?v=5.103&access_token=#{TOKEN}"
  SAVE_UPLOADED_ATTACHMENT     = "#{API}photos.saveMessagesPhoto?v=#{VERSION}&access_token=#{TOKEN}"

  CHART_BASE_URL = 'https://charts.profinance.ru/html/charts/image?SID='
  USD_CHART      = "#{CHART_BASE_URL}avgYq3F8p&s=29&ins1=&ins2=&h=352&w=720&pt=2&tt=1&z=12&ba=0&nw=720&T=1584738953123"
  EUR_CHART      = "#{CHART_BASE_URL}CuGI7py8&s=30&ins1=&ins2=&h=352&w=720&pt=2&tt=1&z=12&ba=0&nw=720&T=1584739124439&left=1"
  BYR_CHART      = "#{CHART_BASE_URL}L4K8Dxk7&s=BYN/RUB&ins1=&ins2=&h=352&w=720&pt=7&tt=1&z=12&ba=0&nw=720&T=1584739265907&left=1"
  LUKOIL_CHART   = "#{CHART_BASE_URL}jG2C0OcZ&s=Lukoil&ins1=&ins2=&h=352&w=720&pt=2&tt=1&z=12&ba=0&nw=720&T=1584739319218"
end

class Miscellaneous
  def self::upload_chart_image(chart_currency, name_of_chart, upload_url)
    result_of_uploading = HTTParty::post(upload_url,
      :body => {
        :photo => (
          image_currency = MiniMagick::Image::open(chart_currency)
          image_currency::write("chart-#{name_of_chart}.png")
          File::open("chart-#{name_of_chart}.png")
        )
      }
    )
    return result_of_uploading
  end
end

class Main
  def self::initialize_variables(
      url_get_longpoll_server,
      send_message,
      get_attachment_upload_server,
      save_uploaded_attachment)
    @@url_get_longpoll_server      = url_get_longpoll_server
    @@send_message                 = send_message
    @@get_attachment_upload_server = get_attachment_upload_server
    @@save_uploaded_attachment     = save_uploaded_attachment
  end

  private
  def self::main
    @@message_text = @@message_text::downcase
    if match_if_command = @@message_text::start_with?(/[\/!]/)
      if match = @@message_text::match(/[\/!](луко[ий]л|lukoil|нефть|
                                              доллар|dollar|usd|
                                              евро|euro?|
                                              бел[ао]рус?ский\sрубль|
                                              byr|byn)/x)
        currency   = match::captures[0x0]
        upload_url = HTTParty::get("#{@@get_attachment_upload_server}&peer_id=#{@@from_id}")
        upload_url = upload_url::parsed_response::to_json
        upload_url = JSON::parse(upload_url)['response']['upload_url']
        case currency
        when /(доллар|dollar|usd)/
          result_of_uploading = Miscellaneous::upload_chart_image(
            BasicConstants::USD_CHART,
            :USD_RUR,
            upload_url
          )
        when /(евро|euro?)/
          result_of_uploading = Miscellaneous::upload_chart_image(
            BasicConstants::EUR_CHART,
            :EUR_RUR,
            upload_url
          )
        when /(бел[ао]рус?ский рубль|byr|byn)/
          result_of_uploading = Miscellaneous::upload_chart_image(
            BasicConstants::BYR_CHART,
            :BYR_RUR,
            upload_url
          )
        when /(луко[ий]л|lukoil|нефть)/
          result_of_uploading = Miscellaneous::upload_chart_image(
            BasicConstants::LUKOIL_CHART,
            :LUKOIL,
            upload_url
          )
        end
        result_of_uploading   = JSON::parse(result_of_uploading)
        uploaded_image_server = result_of_uploading['server']
        uploaded_image_data   = result_of_uploading['photo']
        uploaded_image_hash   = result_of_uploading['hash']

        save_result     = HTTParty::get(<<~SAVE
                                        #{@@save_uploaded_attachment}
                                        &server=#{uploaded_image_server}
                                        &photo=#{uploaded_image_data}
                                        &hash=#{uploaded_image_hash}
                                        SAVE
                                       )
        save_result     = save_result::parsed_response::to_json
        save_result     = JSON::parse(save_result)['response'][0]
        result_owner_id = save_result['owner_id']
        result_image_id = save_result['id']
        HTTParty::get(<<~SEND
                      #{@@send_message}
                      &peer_id=#{@@peer_id}
                      &attachment=photo#{result_owner_id}_#{result_image_id}
                      SEND
                     )
      else
        send_fail_message = URI::escape(<<~SEND::gsub(/\n*/, '')
                                        #{@@send_message}
                                        &peer_id=#{@@peer_id}
                                        &message=Выбрана неверная валюта.
                                        SEND
                                       )
        HTTParty::get(send_fail_message)
      end
    end
  end

  def self::longpoll_listener
    get_server_response = HTTParty::get(@@url_get_longpoll_server)
    key = get_server_response::parsed_response['response']['key']
    ts = get_server_response::parsed_response['response']['ts']
    server = get_server_response::parsed_response['response']['server']

    loop do
      longpoll_response = "#{server}?wait=25&act=a_check&key=#{key}&ts=#{ts}"
      longpoll_response = HTTParty::get(longpoll_response)
      longpoll_response = longpoll_response::parsed_response::to_json
      longpoll_response = JSON::parse(longpoll_response)
      longpoll_failed   = longpoll_response['failed']
      if longpoll_failed == 0x2
        puts longpoll_failed
        get_server_response = HTTParty::get(@@url_get_longpoll_server)
        key = get_server_response::parsed_response['response']['key']
      elsif longpoll_failed == 0x3
        puts longpoll_failed
        get_server_response = HTTParty::get(@@url_get_longpoll_server)
        key = get_server_response::parsed_response['response']['key']
        ts = get_server_response::parsed_response['response']['ts']
      end
      ts = longpoll_response['ts']
      updates = longpoll_response['updates']
      if updates != nil
        size = longpoll_response['updates']::size
      end
      if size == nil
        next
      end
      size -= 0x1
      (0x0..size)::each do |number|
        update = updates[number]
        type_of_update = update['type']
        if type_of_update == 'message_new'
          update_object   = update['object']['message']
          @@message_text  = update_object['text']
          @@from_id       = update_object['from_id']
          @@peer_id       = update_object['peer_id']
          main
        end
      end
    end
  end
end

class Initiate
  def self::start
    loop do
      begin
        Main::initialize_variables(
          BasicConstants::URL_GET_LONGPOLL,
          BasicConstants::SEND_MESSAGE,
          BasicConstants::GET_ATTACHMENT_UPLOAD_SERVER,
          BasicConstants::SAVE_UPLOADED_ATTACHMENT
        )
        Main::longpoll_listener
      rescue => an_error
        puts an_error
        Main::initialize_variables(
          BasicConstants::URL_GET_LONGPOLL,
          BasicConstants::SEND_MESSAGE,
          BasicConstants::GET_ATTACHMENT_UPLOAD_SERVER,
          BasicConstants::SAVE_UPLOADED_ATTACHMENT
        )
        Main::longpoll_listener
      end
    end
  end
end

Initiate::start
