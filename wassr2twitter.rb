#!/bin/ruby -Ku
# -*- coding: utf-8 -*-

#==================================
require 'uri'
require 'open-uri'
require "net/http"
require "rexml/document"
require 'optparse'
require 'timeout'

#==================================
# 初期設定
#==================================
#Oauth設定
#以下のサイトにて、お手数ですが、アプリケーション登録をお願いします。
#Twitter / Applications http://twitter.com/oauth_clients
# 設定では以下のようにしてください
# [Application Name]    : 文字列にTwitterを含まない任意の名前
# [Application Type]    : "Client"
# [Default Access type] : "Read & Write"
consumer_key = '<CONSUMER-KEY>'
consumer_secret = '<CONSUMER-SECRET>'

#wassr ID
wassr_id   = '<wassr id>'
#wassr Passwd
wassr_pw   = '<wassr passwd>'

#twitter ID
twitter_id = '<twitter id>'
#twitter Password
twitter_pw = '<twitter passwd>'

# import ID/PW from ~/.pit
begin
  require 'rubygems'
  require 'pit'

  wassr = Pit::get( 'wassr', :require => {
                      'user' => 'your ID of Wassr.',
                      'pass' => 'your Password of Wassr.',
  } )
  wassr_id = wassr['user']
  wassr_pw = wassr['pass']
  twitter = Pit::get( 'twitter_post', :require => {  
                        'user' => 'your ID of Twitter.',
                        'pass' => 'your Password of Twitter.',
  } )
  twitter_id = twitter['user']
  twitter_pw = twitter['pass']

  oauth_key = Pit::get( 'oauth_consumer_info', :require => {  
                        'key' => 'your Consumer key for OAuth.',
                        'secret' => 'your Consumer secret for OAuth',
  } )
  begin 
      require 'oauth'
      consumer_key = oauth_key['key']
      consumer_secret = oauth_key['secret']
  rescue LoadError
  end 

  begin
    require 'prowl'
    prowl = Pit::get( 'prowl', :require => { 
                        'apikey' => 'your Prowl API Key',
                      })
    prowl_api = prowl['apikey']
    prl = Prowl.new(prowl_api)
  rescue LoadError
  end
rescue LoadError
end

#==================================
# 定数
#==================================
#wassrページの取得数MIN,MAX
#※本アプリとしての制約
wassr_get_pages_min = 1
wassr_get_pages_max = 5


#wassr 投稿用情報
wassr_post_FQDN = 'api.wassr.jp'
wassr_post_URL  = '/statuses/update.json'
wassr_http_port = '80'

#wassr TLのXML取得
wassr_apiUrl_for_TL = 'http://api.wassr.jp/statuses/friends_timeline.xml?'
wassr_apiParam_for_TL = 'page='


#twitter 投稿用情報
#twitter_post_FQDN = 'twitter.com'
#twitter_post_URL  = '/statuses/update.xml'
#twitter_http_port = '80'

twitter_post = 'http://twitter.com/statuses/update.xml'

#twitter access token
twitter_api_for_token = 'https://api.twitter.com'

#twitterのmention取得
twitter_get_mentions = 'http://twitter.com/statuses/mentions.xml?count=200&since_id='
#twitter_apiUrl_for_rep = 'http://twitter.com/statuses/mentions.xml?count=200&'
#twitter_apiParam_for_rep = 'since_id='

#tinyurl api
tinyurl_postUrl = 'http://tinyurl.com/api-create.php?url='
tinyurl_http_port = '80'


#WassrXML要素名（friends_timeline用）
wassr_xml_elem_id = ['user_login_id',
                     'areacode',
                     'photo_thumbnail_url',
                     'html',
                     'reply_status_url',
                     'text',
                     'id',
                     'link',
                     'reply_user_login_id',
                     'epoch',
                     'rid',
                     'photo_url',
                     'reply_message',
                     'reply_user_nick',
                     'slurl',
                     'areaname',
                     'user/protected',
                     'user/profile_image_url',
                     'user/screen_name']
wassr_xml_root_id = 'statuses/status'

#個々の使用する要素定義（for Wassr）
wassr_xml_elem_key = wassr_xml_elem_id[6]
wassr_xml_elem_post_name = wassr_xml_elem_id[0]
wassr_xml_elem_post_text = wassr_xml_elem_id[5]
wassr_xml_elem_post_link = wassr_xml_elem_id[7]
wassr_xml_elem_post_rep  = wassr_xml_elem_id[4]

#TwitterXML要素名（mentions用）
twitter_xml_elem_id = ['created_at',
                       'id',
                       'text',
                       'source',
                       'truncated',
                       'in_reply_to_status_id',
                       'in_reply_to_user_id',
                       'favorited',
                       'in_reply_to_screen_name',
                       'user/id',
                       'user/name',
                       'user/screen_name',
                       'user/location',
                       'user/description',
                       'user/profile_image_url',
                       'user/url',
                       'user/protected',
                       'user/followers_count',
                       'user/profile_background_color',
                       'user/profile_text_color',
                       'user/profile_link_color',
                       'user/profile_sidebar_fill_color',
                       'user/profile_sidebar_border_color',
                       'user/friends_count',
                       'user/created_at',
                       'user/favourites_count',
                       'user/utc_offset',
                       'user/time_zone',
                       'user/profile_background_image_url',
                       'user/profile_background_tile',
                       'user/statuses_count',
                       'user/notifications',
                       'user/following']
twitter_xml_root_id = 'statuses/status'

#TwitterXMLの各発言要素ID
twitter_xml_elem_key = twitter_xml_elem_id[1]
twitter_xml_elem_post_name = twitter_xml_elem_id[11]
twitter_xml_elem_post_text = twitter_xml_elem_id[2]

#個々の使用する要素定義（for Twitter）

#ID保存ファイル
id_file_name_wassr = '.wassr_id'
id_file_name_twitter = '.twitter_id'

#リクエストトークン情報保存ファイル
$req_token_file_name = '.token_info'

#==================================
# 変数
#==================================
#wassrのタイムラインを監視するか？(trueでないと、このスクリプトの存在意義が…)
wassr2twitter = true

#Twitterのタイムラインを監視するか？
twitter2wassr = false

#prowl利用
useProwl = false

#Wassrに転送するリプライ元ユーザID
rep_user_ids = Array::new

#Wassrタイムライン取得ページ数
wassr_get_pages = 1

$statuses_hash = Hash::new

$proxy_scheme, $proxy_host, $proxy_port = 
(ENV['http_proxy']||'').scan( %r|^(.*?)://(.*?):(\d+)?| ).flatten

#HTTP接続のタイムアウト時刻
$req_timeout = 10

#Prowl用メッセージ
$prl_message = ''
$prl_num = 0

#アクセストークン
$access_token_token  = '';
$access_token_secret = '';

#==================================
# メソッド
#==================================
#各APIに接続して、情報を取得しハッシュに格納する。
def get_xml(url,
            param_name,
            param_valie,
            loginid,
            passwd,
            xml_root,
            status_id_name,
            read_params)

  begin
    timeout($req_timeout){ 
      result = open(url + param_name + param_valie, 
                    :http_basic_authentication => [loginid, passwd]).read
      
      get_xml_value(result,xml_root,status_id_name,read_params)

    }
  rescue Timeout::Error
    #タイムアウトでスクリプト終了
    exit 0
  rescue Errno::ECONNRESET
    exit 0
  rescue
    exit 0
  end
end

def get_xml_value(response,
            xml_root,
            status_id_name,
            read_params)

  begin
      xmldoc = REXML::Document.new(response)
      
      xmldoc.elements.each(xml_root) do |sts|
        #連想配列に格納後、IDをキーに連想配列に格納
        tmpHash = Hash::new
        read_params.each do |elm|
          tmpHash[elm] = sts.elements[elm].text.to_s
        end
      $statuses_hash[tmpHash[status_id_name]]=tmpHash
      end
  rescue Timeout::Error
    #タイムアウトでスクリプト終了
    exit 0
  rescue Errno::ECONNRESET
    exit 0
  rescue
    exit 0
  end
end

#投稿用の共通処理
def post_entry(host,
               port,
               path,
               id,
               pass,
               body)
  begin
    timeout($req_timeout){
      #投稿
      Net::HTTP.version_1_2
      req = Net::HTTP::Post.new(path)
      req.basic_auth id,pass
      
      req.body = body
      
      Net::HTTP::Proxy( $proxy_host, $proxy_port ).start(host,port) {|http|
        res = http.request(req)
      }
      #連投用の待機
      sleep 1
    }
  rescue Timeout::Error
    #タイムアウトでスクリプト終了
    exit 0
  rescue Errno::ECONNRESET
    exit 0
  rescue
    exit 0
  end
  
end


#最終取得IDを指定ファイルに格納する。
def write_last_id(file_name,id)
  tmp_file = open(file_name,'w')
  tmp_file.puts id
  tmp_file.close
end

#リクエストークン情報を格納する。
def write_token_info()
  tmp_file = open($req_token_file_name,'w')
  tmp_file.puts $access_token_token + ',' + $access_token_secret
  tmp_file.close
end

#最終取得IDを指定ファイルから読み出す
#失敗した場合は0が返される
def read_last_id(file_name)
  begin
    tmp_file = open(file_name)
    id = tmp_file.gets.to_s.strip
    tmp_file.close
  rescue Errno::ENOENT
    id = "1"
  end

  #数値文字列か評価し、おかしかったら0とする
  if id =~ /^[0-9]+$/ then
    id = id.to_i
  else
    id = 1
  end

  return id
end

#トークン情報を読み出す
def read_token_info()
  begin
    tmp_file = open($req_token_file_name)
    tokens = tmp_file.gets.to_s.strip.split(',')
    $access_token_token  = tokens[0]
    $access_token_secret = tokens[1]
    tmp_file.close
  rescue Errno::ENOENT
    token = ''
  end

  return token
end

#文字列が数字のみで構成されているか確認
def chk_num(str)
  if str=~/^[0-9]+$/ then
    return true
  else
    return false
  end
end

#==================================
# コマンドラインオプション
#==================================
opt = OptionParser.new

#オプション情報保持用
opt_hash = Hash::new

begin 
  #コマンドラインオプション定義
  opt.on('-h','--help','USAGEを表示。')    {|v| puts opt.help;exit }

  opt.on('-n page',
         'Wassrのタイムラインを取得するページ数。（Default:1 Min:' << 
         wassr_get_pages_min.to_s << ' Max:' << 
         wassr_get_pages_max.to_s << '）')    {
    |v| opt_hash[:n] = v } 
  
  opt.on('-w bool',
         '--wassr2twitter=bool' ,
         'WassrのタイムラインをTiwtterに投稿する。 true:有効 false:無効 （Default:true）') {
    |v| opt_hash[:w] = v }

  opt.on('-t bool',
         '--twitter2wassr=bool' ,
         'TwitterのMentionsをWassrに投稿する。 true:有効 false:無効 （Default:false）') {
    |v| opt_hash[:t] = v }

  opt.on('-A IDs',
         '--target-account=IDs' ,
         'TwitterのMentionsからWassrに投稿すべきTwitterアカウントを記述する。カンマ区切りで複数指定可能。') {
    |v| opt_hash[:A] = v }

  opt.on('-p',
         '--use-prowl' ,
         'Wassrの投稿をProwlに通知') {
    |v| opt_hash[:p] = v }
  
  #オプションのパース
  opt.parse!(ARGV)
  
rescue
  #指定外のオプションが存在する場合はUsageを表示
  puts opt.help
  exit
end


#アクセストークンが既存か確認


#Access_tokenを取得する。
oauth_consumer = OAuth::Consumer.new(
                                     consumer_key,
                                     consumer_secret,
                                     :site => twitter_api_for_token)

#リクエストトークンを取得
read_token_info

if($access_token_token == '')then
  begin
    access_token = oauth_consumer.get_access_token(
                                                   nil,
                                                   {},
                                                   {:x_auth_mode => "client_auth",
                                                     :x_auth_username => twitter_id,
                                                     :x_auth_password => twitter_pw,})
  #リクエストトークン情報
  $access_token_token = access_token.token
  $access_token_secret = access_token.secret
  #ファイルに書き出し
  write_token_info
  rescue
    puts 'アクセストークンを取得出きませんでした。'
    puts 'リクエストトークンを再取得していただくと問題が解決するかもしれません。'
    exit
  end
else
  #既存情報でアクセストークン作成
  access_token = OAuth::AccessToken.new(
                                        oauth_consumer,
                                        $access_token_token,
                                        $access_token_secret
)


end


#各引数の判定処理
begin
  opt_hash.each { |arg , value| 
    case arg
    when :w
        case value
        when 'true'
          wassr2twitter = true
        when 'false'
          wassr2twitter = false
        else
          raise ArgumentError, "invalid argument"
        end

    when :t
      case opt_hash[:t]
      when 'true'
        twitter2wassr = true
      when 'false'
        twitter2wassr = false
      else
        raise ArgumentError, "invalid argument"
      end
    when :n
      if chk_num(value) then
        wassr_get_pages = value.to_i
        if wassr_get_pages < wassr_get_pages_min or wassr_get_pages > wassr_get_pages_max then 
          raise ArgumentError, "invalid argument"
        end
      else
        raise ArgumentError, "invalid argument"
      end
    when :A
      #カンマ区切りを配列に
      #重複を除去
      rep_user_ids = value.split(',').uniq
    when :p
      useProwl = true
    end
  }
  
rescue
  puts opt.help
  exit
end

#==================================
# 実行
#==================================

if wassr2twitter then
  #読込済みIDを取得する
  id = read_last_id(id_file_name_wassr)

  #BASIC認証を開始し、XMLオブジェクトを取得
  for count in 1..wassr_get_pages do
    get_xml(
            wassr_apiUrl_for_TL,
            wassr_apiParam_for_TL,
            count.to_s,
            wassr_id,
            wassr_pw,
            wassr_xml_root_id,
            wassr_xml_elem_key,
            wassr_xml_elem_id
            )
  end

  #IDでソートしつつ投稿情報を作成
  $statuses_hash.sort{|a,b|
    a[0] <=> b[0]
  }.each {|key, value|
    if id < key.to_i then
      id = key.to_i
      tmp_name = $statuses_hash[key][wassr_xml_elem_post_name]
      tmp_text = $statuses_hash[key][wassr_xml_elem_post_text]
      tmp_link = $statuses_hash[key][wassr_xml_elem_post_link]
      #Prowl用メッセージ文を作成
      #最終メッセージのみを送信する
      $prl_message = tmp_name + ':' + tmp_text
      $prl_num = $prl_num + 1
      
      #tmp_link = open(tinyurl_postUrl + tmp_link.to_s).read.to_s

      #投稿
      #既存のBacis認証部分
      #post_entry(twitter_post_FQDN,
      #           twitter_http_port.to_i,
      #           twitter_post_URL,
      #           twitter_id,
      #           twitter_pw,
      #           'status=' + URI.encode("[ws]" + tmp_name + ":" + tmp_text + "[" + tmp_link+"]")
      #           )
      
      #Oauthで投稿
      access_token.post(twitter_post,{:status => "[ws]" + tmp_name + ":" + tmp_text + "[" + tmp_link+"]"})
    end
  }
  #Prowlに通知
  begin
    if useProwl && $prl_num != 0  then
      prl.send(
               :application => "wassr2twitter",
               :event => $prl_num.to_s + '件のメッセージ',
               :description => $prl_message
               )
    end
    
  rescue
  end
  
  
  #最終IDを書き込む
  write_last_id(id_file_name_wassr,id)
  
  #ハッシュをクリアする
  $statuses_hash.clear
end

#twitter の mentionsをチェック
if twitter2wassr then 
  #最終ID取得
  id = read_last_id(id_file_name_twitter)
  
  #mention情報取得
  response = access_token.get(twitter_get_mentions + id.to_s)
  get_xml_value(
                response.body,
                twitter_xml_root_id,
                twitter_xml_elem_key,
                twitter_xml_elem_id
          )
  #IDでソートしつつ、投稿情報を作成
  $statuses_hash.sort{ |a,b|
    a[0] <=> b[0]
  }.each { |key,value|
    id = key.to_i

    tmp_name = $statuses_hash[key][twitter_xml_elem_post_name]
    tmp_text = $statuses_hash[key][twitter_xml_elem_post_text]
    #指定のIDからのリプライだった場合、投稿する
    if rep_user_ids.index(tmp_name) != nil  then
      #余計な情報(@指定)を取り除く
      tmp_text = tmp_text.sub(/@.+\s/,"")


      post_entry(wassr_post_FQDN,
                 wassr_http_port.to_i,
                 wassr_post_URL,
                 wassr_id,
                 wassr_pw,
                 'source=wassr2twitter&status=' + tmp_text
                 )
      
    end
  }
  #最終IDを書き込む
  write_last_id(id_file_name_twitter,id)
  
  #ハッシュをクリアする
  $statuses_hash.clear

end
    

exit
