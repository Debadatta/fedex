module Fedex
	class LocationService

		attr_accessor :address, :operational_hours

		def initialize(options = {})
			address = options[:address]
			@address = "#{address[:street_lines]}, #{address[:city]}, #{address[:state_or_province_code]}, #{address[:postal_code]}"
			@operational_hours = options[:operational_hours]
		end
	end
end
