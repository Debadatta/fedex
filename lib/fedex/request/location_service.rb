require 'fedex/request/base'
require 'fedex/location_service'
require 'fileutils'


module Fedex
	module Request
		class LocationService < Base
			def initialize(credentials, options={})
				requires!(options, :address)
				@credentials = credentials
				@address     = options[:address]
				@phone_number = options[:phone_number]
				@coordinates ||= options[:coordinates]
				@ship_date ||= options[:ship_date]

				@address[:address] ||= @address[:street]
			end

			def process_request
				api_response = self.class.post(api_url, :body => build_xml)
				puts api_response if @debug == true
				response = parse_response(api_response)
				puts build_xml

				puts "api response"
				puts response.to_yaml
				if success?(response)
					search_locations_reply_details = response[:search_locations_reply][:address_to_location_relationships][:distance_and_location_details] || []
					search_locations_reply_details = [search_locations_reply_details] if search_locations_reply_details.is_a?(Hash)

					search_locations_reply_details.map do |search_locations_reply|
						locations_details = search_locations_reply[:location_detail][:location_contact_and_address]
						locations_details.merge!(operational_hours: search_locations_reply[:location_detail][:normal_hours])
						Fedex::LocationService.new(locations_details)
					end
				else
					error_message = if response[:search_locations_reply]
						                [response[:search_locations_reply][:notifications]].flatten.first[:message]
						              else
							              "#{api_response["Fault"]["detail"]["cause"]}\n--#{api_response["Fault"]["detail"]["desc"].join("\n--")}"
						              end rescue $1
					raise RateError, "error_message"
				end
			end

			private

			# Build xml Fedex Web Service request
			def build_xml
				builder = Nokogiri::XML::Builder.new do |xml|
					xml.SearchLocationsRequest(:xmlns => "http://fedex.com/ws/locs/v3"){
						add_web_authentication_detail(xml)
						add_location_client_detail(xml)
						add_version(xml)
						add_request_timestamp(xml)
						add_location_search_criterion(xml)
						add_unique_tracking_number(xml)
						add_origin_address(xml)
						add_phone_number(xml)
						add_geographic_coordinates(xml)
					}
				end
				builder.doc.root.to_xml
			end

			def add_user_credential(xml)
				 xml.UserCredential {
					 xml.Key  @credentials.key
					 xml.Password @credentials.password
				 }
			end

			def add_location_client_detail xml
				xml.ClientDetail{
					xml.AccountNumber @credentials.account_number
					xml.MeterNumber @credentials.meter
					xml.Region  'US'
				}
			end

			# Add Version to xml request, using the version identified in the subclass
			def add_version(xml)
				xml.Version{
					xml.ServiceId service[:id]
					xml.Major     service[:version]
					xml.Intermediate 0
					xml.Minor 0
				}
			end
			def add_request_timestamp(xml)
				timestamp = (Time.now + 2.days).in_time_zone(LABEL_TIMEZONE).strftime("%Y-%m-%d")
				xml.EffectiveDate timestamp
			end

			def add_address_validation_options(xml)
				xml.Options{
					xml.CheckResidentialStatus true
				}
			end
			def add_location_search_criterion(xml)
				xml.LocationsSearchCriterion 'ADDRESS'
			end

			def add_unique_tracking_number(xml)
				timestamp = (Time.now + 2.days).in_time_zone(LABEL_TIMEZONE).strftime("%Y-%m-%d")
				xml.UniqueTrackingNumber {
					xml.TrackingNumber
					xml.TrackingNumberUniqueIdentifier
					xml.ShipDate timestamp
				}
			end
			def add_origin_address(xml)
				xml.Address{
					xml.StreetLines         @address[:address]
					xml.City                @address[:city]
					xml.StateOrProvinceCode
					xml.PostalCode          @address[:postal_code]
					xml.UrbanizationCode
					xml.CountryCode         @address[:country]
					xml.Residential         0
				}
			end

			def add_phone_number(xml)
				xml.PhoneNumber @phone_number
			end

			def add_geographic_coordinates(xml)
				xml.GeographicCoordinates  @coordinates
				xml.MultipleMatchesAction  "RETURN_ALL"
				xml.SortDetail {
					xml.Criterion "DISTANCE"
					xml.Order 'LOWEST_TO_HIGHEST'
				}
				xml.Constraints {
					xml.RadiusDistance {
						xml.Value   '100'
						xml.Units  'KM'
					}
					#xml.ResultsFilters 'EXCLUDE_LOCATIONS_OUTSIDE_STATE_OR_PROVINCE'
					#xml.SupportedRedirectToHoldServices 'FEDEX_GROUND'
					xml.RequiredLocationAttributes 'DANGEROUS_GOODS_SERVICES'
					xml.ResultsRequested 10
					#xml.LocationContentOptions 'LOCATION_DROPOFF_TIMES'
					#xml.LocationTypesToInclude 'FEDEX_AUTHORIZED_SHIP_CENTER'
				}
			end

			def service
				{ :id => 'locs', :version => 3 }
			end

			# Successful request
			def success?(response)
				response[:search_locations_reply] &&
						%w{SUCCESS WARNING NOTE}.include?(response[:search_locations_reply][:highest_severity])
			end

		end
	end
end
