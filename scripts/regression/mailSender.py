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

# me == my email address
# you == recipient's email address
me = senderUsername+"@mellanox.com"
you = mailTo+"@mellanox.com;amirh@mellanox.com;avnerb@mellanox.com;idanwe@mellanox.com;alexr@mellanox.com;oriz@mellanox.com;katyak@mellanox.com"

# Create message container - the correct MIME type is multipart/alternative.
msg = MIMEMultipart('alternative')
msg['Subject'] = headline
msg['From'] = me
msg['To'] = you


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
s.sendmail(me, you, msg.as_string())
s.quit()
