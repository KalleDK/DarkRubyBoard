require "net/https"
require "uri"
require "openssl"
require "io/console"
require "yaml"

header = {
	'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/54.0.2840.71 Safari/537.36',
	'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
	'Accept-Encoding' => 'deflate',
	'Accept-Language' => 'en-US,en;q=0.8'
}

class CookieJar
   def initialize
      @cookies = Hash.new{|h, k| h[k] = {}}
   end
   
   def get_cookies(uri)
      @cookies[uri.host]
   end
   
   def set_cookies(uri, cookies)
      @cookies[uri.host].update(cookies)
   end
   
   def get_header_cookies(uri)
      self.get_cookies(uri).map{|k,v| "#{k}=#{v}"}.join(';')
   end

   def set_header_cookies(uri, cookies)
      self.set_cookies(
         uri,
         cookies.map{ |cookie| [
                        cookie.split('; ')[0].split('=')[0], 
                        cookie.split('; ')[0].split('=')[1]
                      ] }.to_h
      ) unless cookies.nil?
   end

   def empty?(uri)
      @cookies[uri.host].empty?
   end
end


class WebClient  
   def initialize(header)  
      @referer = nil
      @cookiejar = CookieJar.new
      @header = header.clone
   end
  
   def get_header(uri)
      header = @header.clone
      header['Cookie'] = @cookiejar.get_header_cookies(uri) unless @cookiejar.empty?(uri)
      header['Referer'] = @referer unless @referer.nil?
      return header
   end

   def parse_header(uri, header)
      @cookiejar.set_header_cookies(uri, header.get_fields('Set-Cookie'))
      if header.code == "200"
         @referer = uri.to_s
      end
   end
  
   def get_http(uri)  
      http = Net::HTTP.new(uri.host, uri.port)
      if uri.scheme == "https"
         http.use_ssl = true
         http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      return http
   end
  
   def set_cookie(uri, key, val)
      @cookies[key] = val
   end
   
   def request(request)
      puts request.uri.scheme + "://" + request.uri.host + request.uri.path
      http = self.get_http(request.uri)
      response = http.request(request)
      self.parse_header(request.uri, response.header)
      if response.header.code == "302"
         puts "Redirected"
         response = self.get(response.header["location"]) 
      end
      if response.header.code == "301"
         puts "Redirected Perm: " + response.header["location"]
         response = self.get(request.uri.scheme + "://" + request.uri.host + response.header["location"]) 
      end
      return response
   end
  
   def get(url)
      uri = URI.parse(url)
      header = self.get_header(uri)
      request = Net::HTTP::Get.new(uri, header)
      self.request(request)
   end
  
   def post(url, data)
      uri = URI.parse(url)
      header = self.get_header(uri)
      request = Net::HTTP::Post.new(uri, header)
      request.set_form_data(data)
      self.request(request)
  end
end

print "Username: "
user = gets.chomp
print "Password: "
pass = STDIN.noecho(&:gets).chomp

client = WebClient.new header
resp = client.get("https://bb.au.dk")
resp = client.get("https://bb.au.dk/webapps/portal/execute/defaultTab")
resp = client.get("https://bb.au.dk/webapps/portal/execute/tabs/tabAction?tab_tab_group_id=_21_1")
resp = client.get("https://bb.au.dk/webapps/bb-auth-provider-shibboleth-BBLEARN/execute/shibbolethLogin?returnUrl=https%3A%2F%2Fbb.au.dk%2Fwebapps%2Fportal%2Fframeset.jsp&authProviderId=_102_1")
resp = client.post(resp.uri.to_s, {'username' => user, 'password' => pass})
resp = client.post('https://wayf.wayf.dk/module.php/saml/sp/saml2-acs.php/wayf.wayf.dk', {'SAMLResponse' => resp.body.split('value="')[1].split('"')[0]})
resp = client.post('https://bb.au.dk/Shibboleth.sso/SAML2/POST', {'SAMLResponse' => resp.body.split('value="')[1].split('"')[0], 'RelayState' => resp.body.split('value="')[2].split('"')[0]})

puts /<title>(.*)<\/title>/.match(resp.body)
