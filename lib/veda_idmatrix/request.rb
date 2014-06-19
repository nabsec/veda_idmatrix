class VedaIdmatrix::Request < ActiveRecord::Base
  self.table_name = "veda_idmatrix_requests"
  self.primary_key = :id
  has_one :response, dependent: :destroy, inverse_of: :request
  serialize :access
  serialize :entity
  
  validates :entity, presence: true
  after_initialize :set_defaults, :to_soap

  def self.access
    begin
      dev_config = YAML.load_file( File.expand_path( '../../lib/config/veda_idmatrix.yml', File.dirname(__FILE__) ) )

      {
        :url => dev_config["url"],
        :access_code => dev_config["access_code"],
        :password => dev_config["password"]
      }
    rescue 
      {
        :url => "Copy 'lib/templates/veda_idmatrix.yml' to 'lib/config/veda_idmatrix.yml' and fill in access details.",
        :access_code => "Copy 'lib/templates/veda_idmatrix.yml' to 'lib/config/veda_idmatrix.yml' and fill in access details.",
        :password => "Copy 'lib/templates/veda_idmatrix.yml' to 'lib/config/veda_idmatrix.yml' and fill in access details."
      }
    end
  end

  def set_defaults
    if self.access.nil? 
      self.access = {
        :url => VedaIdmatrix::Request.access[:url],
        :access_code => VedaIdmatrix::Request.access[:access_code],
        :password => VedaIdmatrix::Request.access[:password]
      }
    end
  end

  def schema
    fname = File.expand_path( '../../lib/assets/idmatrix-v4-0-2.xsd', File.dirname(__FILE__) )
    File.read(fname)
  end

  def to_soap
    if self.entity
      self.to_xml_body
      self.soap = self.add_envelope(self.xml, self.access[:url], self.access[:access_code], self.access[:password], 'message_id')
    else
      "No entity details - set your entity hash"
    end
  end

  def to_xml_body
    doc = self.to_dom('request', self.id_matrix_operation, {:'client-reference'=>"Connect Guide Ref", :'reason-for-enquiry'=>"Connect Guide Reason"}).to_xml.gsub(/(<[\/]?)/,'\1idm:')
    self.xml = doc.gsub('<idm:?xml version="1.0"?>','')
  end

  def to_dom(node, data, attrs={} )
    doc = Nokogiri::XML::Builder.new do |builder|
      if data.is_a? Hash
        builder.send(node, attrs) do
          data.keys.each do |k|
            builder  << to_dom(k, data[k]).root.to_xml
          end
        end
      else
        builder.send(node, data)
      end
    end
    doc.doc
  end

  def id_matrix_operation
  
    individual_name = {
      :'family-name' => (self.entity[:family_name]).to_s,
      :'first-given-name' => (self.entity[:first_given_name]).to_s,
    }
    individual_name = individual_name.merge(:'other-given-name' => (self.entity[:other_given_name]).to_s) if !self.entity[:other_given_name].blank? #rescue false

    date_of_birth = (self.entity[:date_of_birth]) #.strftime("%Y-%m-%d")
    gender = (self.entity[:gender].downcase)

    current_address = {
      :'property' => (self.entity[:current_address][:property]),
      :'unit-number' => (self.entity[:current_address][:unit_number]),
      :'street-number' => (self.entity[:current_address][:street_number]),
      :'street-name' => (self.entity[:current_address][:street_name]),
      :'street-type' => (self.entity[:current_address][:street_type]),
      :'suburb' => (self.entity[:current_address][:suburb]),
      :'state' => (self.entity[:current_address][:state]),
      :'postcode' => (self.entity[:current_address][:postcode]),
    }
    current_address.delete(:'unit-number') if self.entity[:current_address][:unit_number].blank? #rescue true

    phone = {
      :'numbers' => {
        :'home-phone-number verify="true"' => (self.entity[:home_phone_number]),
        :'mobile-phone-number verify="true"' => (self.entity[:mobile_phone_number])
      }
    }

    email_address = (self.entity[:email_address])
    drivers_licence_details = {
      :'state-code' => (self.entity[:drivers_licence_state_code]),
      :'number' => (self.entity[:drivers_licence_number])
    }
    if self.entity[:drivers_licence_state_code] == "VIC"
      drivers_licence_details = drivers_licence_details.merge(:"captcha-challenge" => (self.entity[:drivers_licence_captcha_challenge]))
      drivers_licence_details = drivers_licence_details.merge(:"captcha-response" => (self.entity[:drivers_licence_captcha_response]))
    end

    if self.entity[:drivers_licence_state_code] == "NSW"
      drivers_licence_details = drivers_licence_details.merge(:"card-number" => (self.entity[:drivers_license_card_number]))
    end

    return {
        :'individual-name' => individual_name,
        :'date-of-birth' => date_of_birth,
        :'gender' => gender,
        :'current-address' => current_address,
        :'phone' => phone,
        :'email-address' => email_address,
        :'drivers-licence-details' => drivers_licence_details
    }
  end

  def add_envelope(xml_message, url, username, password, message_id)
    "<soapenv:Envelope
      xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\"
      xmlns:wsse=\"http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd\"
      xmlns:wsa=\"http://www.w3.org/2005/08/addressing\"
      xmlns:vh=\"http://vedaxml.com/soap/header/v-header-v1-7.xsd\"
      xmlns:idm=\"http://vedaxml.com/vxml2/idmatrix-v4-0.xsd\">
      <soapenv:Header>
        <wsse:Security>
          <wsse:UsernameToken>
            <wsse:Username>#{username}</wsse:Username>
            <wsse:Password>#{password}</wsse:Password>
          </wsse:UsernameToken>
        </wsse:Security>
        <wsa:ReplyTo>
          <wsa:Address>http://www.w3.org/2005/08/addressing/anonymous</wsa:Address>
        </wsa:ReplyTo>
        <wsa:To>#{url}</wsa:To>
        <wsa:Action>http://vedaxml.com/idmatrix/VerifyIdentity</wsa:Action>
        <wsa:MessageID>#{message_id}</wsa:MessageID>
      </soapenv:Header>
      <soapenv:Body>#{xml_message}</soapenv:Body>
    </soapenv:Envelope>"
  end

  def validate_xml
    if self.xml
      xsd = Nokogiri::XML::Schema(self.schema)
      doc = Nokogiri::XML(self.xml)
      xsd.validate(doc).each do |error|
        error.message
      end
    else
      "No xml to validate! - run to_soap"
    end
  end

  def post
    if self.soap
      headers = {'Content-Type' => 'text/xml', 'Accept' => 'text/xml'}
      HTTParty.post(self.access[:url], :body => self.soap, :headers => headers)
    else
      "No soap envelope to post! - run to_soap"
    end
  end

  def post_and_capture
    post = self.post
    # self.save
    VedaIdmatrix::Response.new(xml: post.body, headers: post.headers, code: post.code, success: post.success?, request_id: self.id) 
  end

end