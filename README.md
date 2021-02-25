# zammad-nowsms
Zammad 2-Way SMS implementation for the NowSMS local Gateway
(https://www.nowsms.com/)

The package is full included in the nowsms.rb file.

To change/update the current package:
 * File nowsms.rb: adapt the code
 * File nowsms-sms.szpm: adapt the package description
 * Base64 encode the file nowsms.rb and insert it in the "content" pair of the JSON object "files" in nowsms-sms.szpm
 * That's it! Your new package is ready!