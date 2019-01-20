#!/usr/bin/python
# -*- coding: latin-1 -*-
#
# Usage example:  env aws_access_key=XXXX aws_secret_key=YYYY dar_glacier_upload  <vault> <filename> <description>
# 
# 

import sys
import os, datetime
import boto.glacier.layer2
from pytz import timezone

# *** Check configuration and run parameters. ***
access_key_id=os.environ.get('aws_access_key_id', None)
secret_access_key=os.environ.get('aws_secret_access_key', None)
region_name=os.environ.get('aws_region_name', "eu-west-1")

if len(sys.argv) != 3 or access_key_id == None or secret_access_key == None:
	print "Usage " + sys.argv[0] + " <vault name> <filename>"
	print "Specify aws_access_key_id, aws_secret_access_key and aws_region_name as environment variables."
	sys.exit(2)
else:
	vault_name = sys.argv[1]
	filename = sys.argv[2]

if(os.path.isfile(filename) == False):
    print("Cannot find the file " + filename + "!");
    sys.exit(1);
 
# *** Initialize glacier API ***
glacier_layer1 = boto.glacier.layer1.Layer1(aws_access_key_id=access_key_id, aws_secret_access_key=secret_access_key,region_name=region_name)

# *** Prepare Upload
# Filename der Kommandozeile entnehmen. Pfad abschneiden und nur den Dateinamen fuer die description verwenden.

# Was als Modification Date verwenden?
dt = datetime.datetime.utcfromtimestamp(os.path.getmtime(filename))
tz = timezone('Europe/Berlin')
loc_dt = tz.localize(dt)

# ** Format für FastGlacier Client.
#archive_description="<m>\
#<v>2</v>\
#<p>" + b64encode(filename.rsplit('/',0)[0]) + "</p>\
#<lm>" +"yyyyMMdd\\THHmmss\\Z" + "</lm>\
#</m>"

# *** Format für CloudBerry Explorer, ist FastGlacier kompatibel.
#{"Path":"sofastats-1.3.2+AF8-for+AF8-win.zip","UTCDateModified":"20130406T221257Z"}
#archive_description='{"Path":"' + filename.rsplit('/',1)[-1].decode('latin-1').encode('utf-7') + '","UTCDateModified":"' + loc_dt.strftime('%Y%m%dT%H%M%S%z') + '"}'
archive_description='{"Path":"' + filename.rsplit('/',1)[-1].decode('latin-1').encode('utf-7') + '","UTCDateModified":"' + dt.strftime('%Y%m%dT%H%M%S') + 'Z"}'
#print archive_description

# *** Do upload. ***
uploader = boto.glacier.concurrent.ConcurrentUploader(glacier_layer1, vault_name, 128*1024*1024, 1)

#print "Uploading " + filename + " ..."
 
archive_id = uploader.upload(filename=filename, description=archive_description)

print "Success! Archive ID: " + archive_id

# If you ever want, you can delete the archive on the vault
# with the archive ID.
# v.delete_archive(archiveID)

