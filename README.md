# zammad-nowsms
Zammad 2-Way SMS implementation for the NowSMS local Gateway
(https://www.nowsms.com/)

In NowSMS configuration, the webhook must be defined in the 2-Way configuration, for all (keyword * ) : Run HTTP or Local Command : https://FQDN/api/v1/sms_webhook/ttttooookkkkeeeennnn/?SmsMessageSid=@@FULLSMS@@&AccountSid=sms&From=@@SENDER@@&To=@@RECIP@@&Body=@@FULLSMS@@

The package source is in the nowsms.rb file, and the package is fully inlcuded in nowsms-sms.szpm.

To change/update the current package:
 * File nowsms.rb: adapt the code
 * File nowsms-sms.szpm: adapt the package description
 * Base64 encode the file nowsms.rb and insert it in the "content" pair of the JSON object "files" in nowsms-sms.szpm
 * That's it! Your new package is ready!
