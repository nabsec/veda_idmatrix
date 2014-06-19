class VedaIdmatrix::Response < ActiveRecord::Base
  self.table_name = "veda_idmatrix_responses"
  self.primary_key = :id
  belongs_to :request, dependent: :destroy, inverse_of: :response

  validates :request, presence: true
  validates :xml, presence: true
  validates :code, presence: true
  validates :headers, presence: true
  validates :success, presence: true

  serialize :headers
  serialize :struct

  after_initialize :to_struct

  def to_struct
    if self.xml && self.success?
      self.struct = RecursiveOpenStruct.new(self.to_hash) #["Envelope"]
    else
      "No struct was created, see .error"
    end
  end

  def to_hash
    if self.xml
      Hash.from_xml(self.xml)
    else
      "No hash was created because there was no xml"
    end
  end

  def error
    if self.xml && !self.success?
      self.xml 
    else
      "No error"
    end
  end


end