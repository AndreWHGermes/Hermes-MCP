#!/usr/bin/env python3
import urllib.request, json, time, os, base64
from datetime import datetime

TOKEN = base64.b64decode('ODg4NzE5OTI3NzpBQUVBNlRWekxjb1JhZDdUanFDSGYtem5ocnI4WXRUeUs0WQ==').decode()
LAST_ID_FILE = '/opt/data/hermes_voice_app/last_update_id.txt'
FLAG_FILE = '/opt/data/hermes_voice_app/voice_mode_active.txt'

last_id = 0
if os.path.exists(LAST_ID_FILE):
    with open(LAST_ID_FILE) as f:
        try:
            last_id = int(f.read().strip())
        except:
            last_id = 0

print('[LISTENER] Запущен, last_id=' + str(last_id))

while True:
    try:
        url = 'https://api.telegram.org/bot' + TOKEN + '/getUpdates?offset=' + str(last_id) + '&timeout=30&allowed_updates=%5B%22message%22%5D'
        resp = urllib.request.urlopen(url, timeout=35)
        data = json.loads(resp.read())
        for upd in data.get('result', []):
            uid = upd['update_id']
            msg = upd.get('message', {})
            txt = msg.get('text', '')
            if txt == 'ГОЛОСОВОЙ РЕЖИМ ВКЛ':
                with open(FLAG_FILE, 'w') as f:
                    f.write('1')
                print(datetime.now().strftime('%H:%M:%S') + ' <<< ГОЛОСОВОЙ РЕЖИМ ВКЛ')
            elif txt == 'ГОЛОСОВОЙ РЕЖИМ ВЫКЛ':
                if os.path.exists(FLAG_FILE):
                    os.remove(FLAG_FILE)
                print(datetime.now().strftime('%H:%M:%S') + ' >>> ГОЛОСОВОЙ РЕЖИМ ВЫКЛ')
            last_id = uid + 1
        with open(LAST_ID_FILE, 'w') as f:
            f.write(str(last_id))
    except Exception as e:
        err = str(e)
        if '409' not in err:
            print('[' + datetime.now().strftime('%H:%M:%S') + '] ' + err[:120])
        time.sleep(5)
