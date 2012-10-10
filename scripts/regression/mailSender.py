#!/usr/bin/env python

import smtplib
import sys
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

headline = sys.argv[1]
message = sys.argv[2]
day = sys.argv[3]
senderUsername = sys.argv[4]
mailTo = sys.argv[5]

# sender == my email address
# recipients == recipient's email address
sender = senderUsername+"@mellanox.com"
recipients = mailTo

# Create message container - the correct MIME type is multipart/alternative.
msg = MIMEMultipart('alternative')
msg['Subject'] = headline
msg['From'] = sender
msg['To'] = recipients


# Record the MIME types of both parts - text/plain and text/html.
#part1 = MIMEText(text, 'plain')
part2 = MIMEText(message, 'html')

# Attach parts into message container.
# According to RFC 2046, the last part of a multipart message, in this case
# the HTML message, is best and preferred.
#msg.attach(part1)
msg.attach(part2)

# Send the message via local SMTP server.
s = smtplib.SMTP('localhost')
# sendmail function takes 3 arguments: sender's address, recipient's address
# and message to send - here it is sent as one string.
s.sendmail(sender, recipients.split(","), msg.as_string())
s.quit()
