require 'net/http'
require 'net/https'
require 'uri'
require 'json'

office_location = URI::encode('53.733741,-1.589997')
key = URI::encode('!!!INSERT free api key from http://developer.tomtom.com/!!!')
locations = []
locations << { name: "Kev", location: URI::encode('53.8059208,-1.6758144'), warn_minutes: 50, alert_minutes: 60 }

SCHEDULER.every '10m', :first_in => '15s' do |job|
   routes = []

   title = "Time Home"
   if Time.now.hour < 12
      title = "Journey In"
   end

   # pull data
   locations.each do |location|
      start_location = office_location
      end_location = location[:location]
      if Time.now.hour < 12
         start_location = location[:location]
         end_location = office_location
      end

      uri = URI.parse("https://api.tomtom.com/lbs/services/route/3/#{start_location}:#{end_location}/Quickest/json?avoidTraffic=true&includeTraffic=true&language=en&day=today&time=now&iqRoutes=2&avoidTolls=false&includeInstructions=true&projection=EPSG4326&key=#{key}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      routes << { name: location[:name], location: location[:location], warn_minutes: location[:warn_minutes], alert_minutes: location[:alert_minutes], route: JSON.parse(response.body)["route"] }
   end

   # find winner
   if routes
      routes.sort! { |route1, route2| route2[:route]["summary"]["totalTimeSeconds"] <=> route1[:route]["summary"]["totalTimeSeconds"] }
      routes.map! do |r|
         { name: r[:name],
            time: seconds_in_words(r[:route]["summary"]["totalTimeSeconds"]),
            road: delay(r[:route]["summary"]["totalDelaySeconds"]) + longest_leg(r[:route]["instructions"]["instruction"]),
            status: route_status(r[:route]["summary"]["totalTimeSeconds"], r[:warn_minutes], r[:alert_minutes])
         }
      end
   end

   # send event
  send_event('tomtom', { title: title, results: routes } )
end

def route_status(secs, warn_minutes, alert_minutes)
  m, s = secs.divmod(60)
  if m >= alert_minutes
    "alert"
  elsif m >= warn_minutes
    "warn"
  else
    "ok"
  end
end

def seconds_in_words(secs)
   m, s = secs.divmod(60)
   h, m = m.divmod(60)

   plural_hours = if h > 1 then "s" else "" end
   plural_minutes = if m > 1 then "s" else "" end

   if secs >= 3600
      "#{h} hour#{plural_hours}, #{m} min#{plural_minutes}"
   else
      "#{m} min#{plural_minutes}"
   end
end

def longest_leg(instructions)
   instructions.sort! { |leg1, leg2| leg2["travelTimeSeconds"] <=> leg1["travelTimeSeconds"] }
   if instructions[0]["roadNumber"].empty?
      instructions[0]["roadName"]
   elsif instructions[0]["roadName"].empty?
      instructions[0]["roadNumber"]
   else
      "#{instructions[0]["roadName"]}, #{instructions[0]["roadNumber"]}"
   end
end

def delay(delay_seconds)
   m, s = delay_seconds.divmod(60)
   h, m = m.divmod(60)

   if delay_seconds >= 60
      "#{m} min delay on "
   elsif delay_seconds == 0
      ""
   else
      "#{s} sec delay on "
   end
end
