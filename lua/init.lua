require('ap_credentials')

require('ds18b20')

-------------------------- CONFIG START ----------------------
FREQ    = 20000
KEY     = 'KEYKEYKEYKEYKEY'
----------- CONFIG -----------

TIMEOUT    		= 30*1000000 -- 30s
MAIN       		= "main.lua"

TCP_SRV_PORT	= 2323
CFG_AP={
	ssid="TERMOMETR_CFG3",
	pwd="12345678",
    max=1,
    beacon=60000
	}
CFG_AP_IP={
	ip="192.168.4.1",
	netmask="255.255.255.0",
	gateway="192.168.4.1"
}
------------------------------

-------- Station modes -------
STAMODE = {
STATION_IDLE             = 0,
STATION_CONNECTING       = 1,
STATION_WRONG_PASSWORD   = 2,
STATION_NO_AP_FOUND      = 3,
STATION_CONNECT_FAIL     = 4,
STATION_GOT_IP           = 5
}
------------------------------


--------------- THINGSPEAK ------------------
ds18b20.setup(3)
ds18b20.read()

function sendData()
        print('thingspeak read start procedure...')
		SENT = SENT+1
        t = ds18b20.read()
		if t == nil then
			print('Error reading temperature, check sensor')
			return
		else
			print('readTemperature')
		end
        t1 = t / 100
        t2 = (t % 100) / 10
		print('konkat')
        --print("Temp:".. t1 .. "." .. t2)
        -- conection to thingspeak.com
        print("Sending data to thingspeak.com")
        conn=net.createConnection(net.TCP, 0) 
        conn:on("receive", function(conn, payload) print(payload) end)
        -- api.thingspeak.com 184.106.153.149
        conn:connect(80,'184.106.153.149') 
        conn:send("GET /update?key="..KEY.."&field1="..t1 .. "." .. t2.." HTTP/1.1\r\n") 
        conn:send("Host: api.thingspeak.com\r\n") 
        conn:send("Accept: */*\r\n") 
        conn:send("User-Agent: Mozilla/4.0 (compatible; esp8266 Lua; Windows NT 5.1)\r\n")
        conn:send("\r\n")
        conn:on("sent",function(conn)
                              print("Sent data. Closing connection")
                              conn:close()
                          end)
        conn:on("disconnection", function(conn)
										SENT = 0
                                        print("Got disconnection...")
          end)
end
----------------- END THINGSPEAK ---------------------

--------------- TCP_SERVER---------------
function startSRV()
    print('Stopping trying to connect to AP, stopping trying to upload data')
	tmr.stop(1)
	tmr.stop(3)
    --print('Setting TCP telnet server on ' .. CFG_AP_IP.ip .. ':' .. TCP_SRV_PORT) 
    -- a simple telnet server
    s=net.createServer(net.TCP, 30) 
    s:listen(TCP_SRV_PORT,CFG_AP_IP.ip,function(c) 
       con_std = c 
       function s_output(str) 
          if(con_std~=nil) 
             then con_std:send(str) 
          end 
       end 
       node.output(s_output, 0)   -- re-direct output to function s_ouput.
       c:on("receive",function(c,l) 
          node.input(l)           -- works like pcall(loadstring(l)) but support multiple separate line
       end) 
       c:on("disconnection",function(c) 
          con_std = nil 
          node.output(nil)        -- un-regist the redirect output function, output goes to serial
       end) 
    end)
    print('Set up a TCP telnet SRV')
end

function setSTATION(ssid, pwd)
	file.remove("ap_credentials.lua");
    file.open("ap_credentials.lua","w+");
	w = file.writeline
	w('SSID="' .. ssid .. '"');
	w('PASSWORD="' .. pwd .. '"');
	file.close();
	print("AP credentials set OK")
end

------------ END TCP SERVER -----------------

------------ STATION ------------------------

CONNECTED = false
-- Function connect: ------
--      connects to a predefined access point
--      params: 
 --        timeout int    : timeout in us
--------------------------
function connect(timeout)
   local time = tmr.now()
   wifi.sta.connect()

   -- Wait for IP address; check each 1000ms; timeout
   tmr.alarm(1, 5000, 1, 
      function() 
         if wifi.sta.status() == STAMODE.STATION_GOT_IP then
            print('checking INET connection ...')
			if CONNECTED == false then
               --tmr.stop(1)
               tmr.stop(2) -- stop starting telnet srv
                  print("Station: connected! IP: " .. wifi.sta.getip())
                  wifi.setmode(wifi.STATION)
				  tmr.alarm(3, FREQ, 1, sendData)
				  CONNECTED = true
			else if ( SENT < 10 ) then
                print('OK')
            else
                node.restart()
            end
            end

         else
                     if tmr.now() - time > timeout then
                        tmr.stop(1)
                        print("Timeout!")
                        connect(TIMEOUT)
                        if wifi.sta.status() == STAMODE.STATION_IDLE          then print("Station: idling") end
                        if wifi.sta.status() == STAMODE.STATION_CONNECTING       then print("Station: connecting") end
                        if wifi.sta.status() == STAMODE.STATION_WRONG_PASSWORD    then print("Station: wrong password") end
                        if wifi.sta.status() == STAMODE.STATION_NO_AP_FOUND    then print("Station: AP not found") end
                        if wifi.sta.status() == STAMODE.STATION_CONNECT_FAIL    then print("Station: connection failed") end
                  end
         end 
      end
   )
end

---------------END STATION ------------------



-- Main
-- 802.11b
wifi.setphymode(wifi.PHYMODE_B)
-- restore wifi settings (?)
node.restore()
-- disconnect from wifi, prevents buffer overflow in routers ?
wifi.sta.disconnect()

print("Setting up Wi-Fi connection..")
wifi.setmode(wifi.STATIONAP)
wifi.sta.config(SSID, PASSWORD)
connect(TIMEOUT)

SENT = 0

print("Setting up Wi-Fi AP..")
wifi.ap.config(CFG_AP)
wifi.ap.setip(CFG_AP_IP)

tmr.alarm(2, 30000, 0, startSRV)
