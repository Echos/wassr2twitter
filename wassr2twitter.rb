#!/bin/ruby -Ku
# -*- coding: utf-8 -*-

#==================================
require 'uri'
require 'open-uri'
require "net/http"
require "rexml/document"

#==================================
# 初期設定
#==================================
#wassr ID
wassr_id   = '<wassr id>'
#wassr Passwd
wassr_pw   = '<wassr passwd>'
#取得ページ数
wassr_get_pages = 1

#twitter ID
twitter_id = '<twitter id>'
#twitter Password
twitter_pw = '<twitter passwd>'

# import ID/PW from ~/.pit
begin
  require 'rubygems'
  require 'pit'
  wassr = Pit::get( 'wassr' )
  wassr_id = wassr['user']
  wassr_pw = wassr['pass']
  twitter = Pit::get( 'twitter_post' )
  twitter_id = twitter['user']
  twitter_pw = twitter['pass']
rescue LoadError
end

http_port = '80'

#==================================
# 定数
#==================================
#wassr TLのXML取得
wassr_apiUrl_for_TL = 'http://api.wassr.jp/statuses/friends_timeline.xml'
http_port = '80'
wassr_apiParam_for_TL = 'page='

#twitter 投稿用情報
twitter_post_FQDN = 'twitter.com'
twitter_post_URL  = '/statuses/update.xml'
twitter_http_port = '80'

#tinyurl api
tinyurl_postUrl = 'http://tinyurl.com/api-create.php?url='
tinyurl_http_port = '80'


#XML要素名
xml_elem_id = ['user_login_id',
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

xml_elem_key = xml_elem_id[6]
xml_elem_post_name = xml_elem_id[0]
xml_elem_post_text = xml_elem_id[5]
xml_elem_post_link = xml_elem_id[7]
xml_elem_post_rep  = xml_elem_id[4]

#ID保存ファイル
id_file_name = '.wassr_id'

#==================================
# 変数
#==================================
statuses_hash = Hash::new

#==================================
# 実行
#==================================
#読込済みIDを取得する
begin
  tmp_file = open(id_file_name)
  id = tmp_file.gets.to_s.strip
  tmp_file.close
rescue Errno::ENOENT
  id = "0"
end

#数値文字列か評価し、おかしかったら0とする
if id =~ /^[0-9]+$/ then
  id = id.to_i
else
  id = 0
end



#BASIC認証を開始し、XMLオブジェクトを取得
for count in 1..wassr_get_pages do
  result = open(wassr_apiUrl_for_TL + '?' + wassr_apiParam_for_TL + count.to_s, 
                :http_basic_authentication => [wassr_id, wassr_pw]).read
  xmldoc = REXML::Document.new(result)

  xmldoc.elements.each('statuses/status') do |sts|
    #連想配列に格納後、IDをキーに連想配列に格納
    tmpHash = Hash::new
    xml_elem_id.each do |elm|
      tmpHash[elm] = sts.elements[elm].text.to_s
    end
    statuses_hash[tmpHash[xml_elem_key]]=tmpHash
  end
end

#IDでソートしつつ投稿情報を作成
statuses_hash.sort{|a,b|
  a[0] <=> b[0]
}.each {|key, value|
  p key
  if id < key.to_i then
    id = key.to_i
    tmp_name = statuses_hash[key][xml_elem_post_name]
    tmp_text = statuses_hash[key][xml_elem_post_text]
    tmp_link = statuses_hash[key][xml_elem_post_link]
    tmp_link = open(tinyurl_postUrl + tmp_link.to_s).read.to_s

    #投稿
    Net::HTTP.version_1_2
    req = Net::HTTP::Post.new(twitter_post_URL)
    req.basic_auth twitter_id,twitter_pw
    req.body = 'status=' + URI.encode("[ws]" + tmp_name + ":" + tmp_text + "[" + tmp_link+"]")

    Net::HTTP.start(twitter_post_FQDN,twitter_http_port.to_i) {|http|
      res = http.request(req)
    }
    sleep 1
  end
}

#最終IDを書き込む
tmp_file = open(id_file_name,'w')
tmp_file.puts id
tmp_file.close

exit
