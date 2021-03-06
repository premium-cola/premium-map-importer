#! /usr/bin/env ruby

require 'iconv'
require 'csv'
require 'json'

class Array
  def self.lit(*a)
    a
  end

  def head
    self[0]
  end

  def tail
    self[1..-1]
  end

  def with_index *a
    self.each_with_index(*a)
  end

  def pluck *a
    ci = self.clone
    ci.delete(*a)
    ci
  end
end

# Give all the fields to be imported sane, English names
FieldMap = Hash \
  Vorname: :first_name,
  Name:    :last_name,
  Firma:   :company,
  Straße:  :street,
  PLZ:     :zipcode,
  Ort:     :city,
  Land:    :country,
  Telefon: :telephone,
  Web:     :web,
  :"E-Mail" => :email,
  Inaktiv: :inactive, # We only store this to remove those
  Gruppen: :groups    # We remap those (csv in csv. really?)

# Group index => role of the entity
RoleMap = Hash \
  7 => :speaker,
  8 => :store,
  9 => :merchant

# Group index => product
ProductMap = Hash \
  2  => :cola,
  20 => :cola,
  21 => :beer,
  22 => [:cola, :beer],
  28 => :appleelder,
  29 => :frohlunder,
  33 => :muntermate
  # 23 => "Premium-Kaffee" # Former

# We hide some fields on speakers for privacy reasons
SpeakerFields = Array.lit :first_name, :last_name, :company,
    :plz, :city, :telephone, :fax, :website, :email, :roles,
    :products

def parse_row(row, csv_headers)
  # Convert the row to a hash; apply the header mapping
  # above; ignore any empty stuff
  row = row.with_index.inject({}) do |h, vi|
      val, idx = vi

      csv_head = csv_headers[idx]
      nu_head = FieldMap[csv_head.to_sym]
      
      
      h[nu_head] = val
      h
  end

  # Discard empty values/keys
  row.reject! do |k,v|
       k.nil? || ( k.is_a?(String) && k.strip.empty? ) \
    || v.nil? || ( v.is_a?(String) && v.strip.empty? )
  end

  # Skip inactives
  return nil if row[:inactive].to_i != 0
  row.delete :inactive

  # Parse the groups value and get rid of it
  gr = row[:groups].to_s.split(/[,.]/).map(&:to_i)
  row.delete :groups

  # Ignore past partners
  return nil if gr.include?(16) || gr.include?(17)

  # Move the crazy groups value in two array fields:
  # products and roles
  row[:products] = gr
      .map {|gi| ProductMap[gi] }
      .pluck(nil)
      .flatten
  row[:roles] = gr
      .map {|gi| RoleMap[gi] }
      .pluck(nil)
      .flatten
  return nil if row[:roles].empty? || row[:products].empty?

  # Speakers do not disclose their exact location
  if row[:roles] == [:speaker]
    row.select! {|k,v| SpeakerFields.include? k }
  end

  row
end

def main
  txtin = Iconv.conv 'UTF-8', "latin1", STDIN.read

  # Parse the plain CSV (I mean semicolon separated *sigh*)
  csv = CSV.parse txtin, col_sep: ';'
  csv_header = csv.head

  # Now parse all the rows
  data = csv.tail
      .map { |row| parse_row row, csv_header }
      .pluck(nil)

  # Aaaand export as json
  JSON.dump data, STDOUT
end

main
